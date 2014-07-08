//
//  CGConnection.m
//  CGConnection
//
//  Created by Chris Galzerano on 7/8/14.
//  Copyright (c) 2014 chrisgalz. All rights reserved.
//

#import "CGConnection.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import "unistd.h"

@interface CGConnection () <NSStreamDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate>

@property (nonatomic, strong) NSString *serviceProtocol;
@property (nonatomic) CFSocketRef socket;
@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) NSNetService *resolvingNetService;
@property (nonatomic, strong) NSNetService *localService;
@property (nonatomic, strong) NSNetServiceBrowser *serviceBrowser;
@property (nonatomic, strong) NSString *domain;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;

@end

@implementation CGConnection {
    NSMutableArray *servicesMutable;
    BOOL inputStreamReady;
    BOOL outputStreamReady;
    BOOL outputStreamHasSpace;
}

static void SocketAcceptedConnectionCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

- (instancetype)initWithServiceType:(NSString*)serviceType
{
    self = [super init];
    if (self) {
        _serviceType = serviceType;
        _serviceProtocol = [self serviceProtocolForServiceType:serviceType];
        _serviceType = [UIDevice currentDevice].name;
        _domain = @"local.";
        servicesMutable = [NSMutableArray new];
    }
    return self;
}

+ (CGConnection*)connectionWithServiceType:(NSString*)serviceType {
    CGConnection *connection = [[CGConnection alloc] initWithServiceType:serviceType];
    return connection;
}

- (NSString*)serviceProtocolForServiceType:(NSString*)serviceType {
    return [NSString stringWithFormat:@"_%@._tcp.", serviceType];
}

- (void)setServiceType:(NSString *)serviceType {
    _serviceType = serviceType;
    _serviceProtocol = [self serviceProtocolForServiceType:serviceType];
}

- (void)startConnection {
    CFSocketContext socketContext = {0, (__bridge void *)(self), NULL, NULL, NULL};
    _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)&SocketAcceptedConnectionCallBack, &socketContext);
    if (_socket) {
        int addressReuse = 1;
        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, (void *)&addressReuse, sizeof(addressReuse));
        uint8_t size = payloadSize;
        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_SNDBUF, (void *)&size, sizeof(size));
        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_RCVBUF, (void *)&size, sizeof(size));
        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        address.sin_port = 0;
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        NSData *addressData = [NSData dataWithBytes:&address length:sizeof(address)];
        if (CFSocketSetAddress(_socket, (__bridge CFDataRef)addressData) == kCFSocketSuccess) {
            NSData *addressDataCopy = (__bridge NSData *)CFSocketCopyAddress(_socket);
            memcpy(&address, [addressDataCopy bytes], [addressDataCopy length]);
            _port = ntohs(address.sin_port);
            CFRunLoopRef runLoop = CFRunLoopGetCurrent();
            CFRunLoopSourceRef runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
            CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopCommonModes);
            CFRelease(runLoopSource);
            if (![self publishNetService]) {
                if ([self.delegate respondsToSelector:@selector(connection:cannotStartWithError:)])
                    [self.delegate connection:self cannotStartWithError:[self errorWithCode:CGConnectionErrorCannotPublishNetService]];
            }
        }
        else {
            if ([self.delegate respondsToSelector:@selector(connection:cannotStartWithError:)])
                [self.delegate connection:self cannotStartWithError:[self errorWithCode:CGConnectionErrorCannotBindIPv4]];
        }
    }
    else {
        if ([self.delegate respondsToSelector:@selector(connection:cannotStartWithError:)])
            [self.delegate connection:self cannotStartWithError:[self errorWithCode:CGConnectionErrorNoSocketsAvailable]];
    }
}

- (void)stopConnection {
    if (_netService) [self stopNetService];
    if (_socket) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    [self stopStreams];
    if ([self.delegate respondsToSelector:@selector(connectionStopped:)])
        [self.delegate connectionStopped:self];
}

- (NSError*)errorWithCode:(CGConnectionError)errorCode {
    return [NSError errorWithDomain:@"CGConnectionErrorDomain" code:errorCode userInfo:nil];
}

- (void)sendData:(NSData *)data {
    if (outputStreamHasSpace) {
        NSInteger len = [self.outputStream write:[data bytes] maxLength:[data length]];
        if (len == -1 || !len) {
            if ([self.delegate respondsToSelector:@selector(connection:failedToSendData:)])
                [self.delegate connection:self failedToSendData:[self errorWithCode:CGConnectionErrorOutputStreamFull]];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(connection:failedToSendData:)])
            [self.delegate connection:self failedToSendData:[self errorWithCode:CGConnectionErrorOutputStreamFull]];
    }
}

- (BOOL)publishNetService {
    _netService = [[NSNetService alloc] initWithDomain:_domain type:_serviceProtocol name:_serviceType port:_port];
    if (_netService) {
        [_netService scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        _netService.delegate = self;
        [_netService publish];
        return YES;
    }
    return NO;
}

- (void)makeConnectionToService:(NSNetService *)service {
    [_resolvingNetService stop];
    _resolvingNetService = nil;
    _resolvingNetService = service;
    _resolvingNetService.delegate = self;
    [_resolvingNetService resolveWithTimeout:0.0];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
    [_resolvingNetService stop];
    _resolvingNetService = nil;
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
	assert(service == _resolvingNetService);
    [_resolvingNetService stop];
    _resolvingNetService = nil;
    [self remoteServiceResolved:service];
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)netServiceBrowser didRemoveService:(NSNetService*)service moreComing:(BOOL)moreComing {
    if([service.name isEqualToString:_resolvingNetService.name]) {
        [_resolvingNetService stop];
        _resolvingNetService = nil;
    } else if([self.localService.name isEqualToString:service.name]) self.localService = nil;
    if ([servicesMutable containsObject:service]) {
        [servicesMutable removeObject:service];
        [self updateServicesArray];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)netServiceBrowser didFindService:(NSNetService*)service moreComing:(BOOL)moreComing {
	if (![service.name isEqualToString:_localService.name]) {
        if (![servicesMutable containsObject:service]) [servicesMutable addObject:service];
        [self updateServicesArray];
    }
}

- (void)updateServicesArray {
    _services = [NSArray arrayWithArray:servicesMutable];
    if ([self.delegate respondsToSelector:@selector(connectionBrowserFoundNewService:)])
        [self.delegate connectionBrowserFoundNewService:self];
}

- (void)netServiceDidPublish:(NSNetService *)service {
    self.localService = service;
	[self searchForServicesOfType:_serviceProtocol];
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorInfo {
    if ([self.delegate respondsToSelector:@selector(connection:cannotStartWithError:)])
        [self.delegate connection:self cannotStartWithError:[self errorWithCode:CGConnectionErrorCannotPublishNetService]];
}

- (void)streamCompletedOpening:(NSStream *)stream {
    if (stream == self.inputStream) inputStreamReady = YES;
    if (stream == self.outputStream) outputStreamReady = YES;
    
    if (inputStreamReady && outputStreamReady) {
        if ([self.delegate respondsToSelector:@selector(connectionStarted:)])
            [self.delegate connectionStarted:self];
        [self stopNetService];
    }
}

- (void)streamHasBytes:(NSStream *)stream {
    NSMutableData *data = [NSMutableData data];
    uint8_t *buf = calloc(payloadSize, sizeof(uint8_t));
    NSUInteger len = 0;
    while([(NSInputStream*)stream hasBytesAvailable]) {
        len = [self.inputStream read:buf maxLength:payloadSize];
        if (len > 0) [data appendBytes:buf length:len];
    }
    free(buf);
    if ([self.delegate respondsToSelector:@selector(connection:receivedData:)])
        [self.delegate connection:self receivedData:data];
}

- (void)streamHasSpace:(NSStream *)stream {
    outputStreamHasSpace = YES;
}

- (void)streamEncounteredEnd:(NSStream *)stream {
    if ([self.delegate respondsToSelector:@selector(connection:lostConnectionWithError:)])
        [self.delegate connection:self lostConnectionWithError:[self errorWithCode:CGConnectionErrorOutputStreamFull]];
    [self stopStreams];
    [self publishNetService];
}

- (void)streamEncounteredError:(NSStream *)stream {
    if ([self.delegate respondsToSelector:@selector(connection:lostConnectionWithError:)])
        [self.delegate connection:self lostConnectionWithError:[stream streamError]];
    [self stopConnection];
}

- (void)remoteServiceResolved:(NSNetService *)remoteService {
    NSInputStream *inputStream = nil;
    NSOutputStream *outputStream = nil;
	if ([remoteService getInputStream:&inputStream outputStream:&outputStream]) {
        [self connectedToInputStream:inputStream outputStream:outputStream];
    }
}

- (void)connectedToInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream {
    [self stopStreams];
    
    _inputStream = inputStream;
    _inputStream.delegate = self;
    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    
    _outputStream = outputStream;
    _outputStream.delegate = self;
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream open];
}

- (void)searchForServicesOfType:(NSString *)type {
	[_serviceBrowser stop];
    _serviceBrowser = nil;
	_serviceBrowser = [[NSNetServiceBrowser alloc] init];
	_serviceBrowser.delegate = self;
	[_serviceBrowser searchForServicesOfType:type inDomain:@"local"];
}

- (void)stopStreams {
    if (_inputStream) {
        [_inputStream close];
        [_inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        _inputStream = nil;
        inputStreamReady = NO;
    }
    if (_outputStream) {
        [_outputStream close];
        [_outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        _outputStream = nil;
        outputStreamReady = NO;
    }
}

- (void)stopNetService {
    [self.netService stop];
    [self.netService removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    self.netService = nil;
}

- (void) stream:(NSStream*)stream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            [self streamCompletedOpening:stream];
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            [self streamHasBytes:stream];
            break;
        }
        case NSStreamEventHasSpaceAvailable: {
            [self streamHasSpace:stream];
            break;
        }
        case NSStreamEventEndEncountered: {
            [self streamEncounteredEnd:stream];
            break;
        }
        case NSStreamEventErrorOccurred: {
            [self streamEncounteredError:stream];
            break;
        }
        default:
            break;
    }
}

static void SocketAcceptedConnectionCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type == kCFSocketAcceptCallBack) {
        CGConnection *connection = (__bridge CGConnection *)info;
        CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
        CFReadStreamRef readStream = NULL;
		CFWriteStreamRef writeStream = NULL;
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, &writeStream);
        if (readStream && writeStream) {
            CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
            CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
            [connection connectedToInputStream:(__bridge NSInputStream *)readStream
                               outputStream:(__bridge NSOutputStream *)writeStream];
        } else close(nativeSocketHandle);
        if (readStream) CFRelease(readStream);
        if (writeStream) CFRelease(writeStream);
    }
}


@end
