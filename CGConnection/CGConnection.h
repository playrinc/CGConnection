//
//  CGConnection.h
//  CGConnection
//
//  Created by Chris Galzerano on 7/8/14.
//  Copyright (c) 2014 chrisgalz. All rights reserved.
//

#import <Foundation/Foundation.h>

#define payloadSize (uint8_t)128

@class CGConnection;

typedef NS_ENUM(NSInteger, CGConnectionError) {
    CGConnectionErrorCannotBindIPv4,
    CGConnectionErrorCannotBindIPv6,
    CGConnectionErrorNoSocketsAvailable,
    CGConnectionErrorCannotPublishNetService,
    CGConnectionErrorOutputStreamFull
};

@protocol CGConnectionDelegate <NSObject>
@optional
- (void)connectionStarted:(CGConnection*)connection;
- (void)connectionStopped:(CGConnection*)connection;
- (void)connection:(CGConnection*)connection cannotStartWithError:(NSError*)error;
- (void)connection:(CGConnection*)connection receivedData:(NSData*)data;
- (void)connection:(CGConnection*)connection failedToSendData:(NSError*)error;
- (void)connection:(CGConnection*)connection lostConnectionWithError:(NSError*)error;
- (void)connectionBrowserFoundNewService:(CGConnection*)connection;
@end

@interface CGConnection : NSObject

@property (nonatomic, strong) NSString *serviceType;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, strong, readonly) NSArray *services;

@property (nonatomic, assign) id<CGConnectionDelegate> delegate;

- (void)makeConnectionToService:(NSNetService*)service;
- (void)startConnection;
- (void)stopConnection;
- (void)sendData:(NSData*)data;

- (instancetype)initWithServiceType:(NSString*)serviceType;
+ (CGConnection*)connectionWithServiceType:(NSString*)serviceType;

@end
