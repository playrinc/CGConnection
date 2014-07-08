//
//  MainVC.m
//  CGConnection
//
//  Created by Chris Galzerano on 7/8/14.
//  Copyright (c) 2014 chrisgalz. All rights reserved.
//

#import "MainVC.h"

@interface MainVC ()

@property (nonatomic, strong) CGConnection *connection;

@end

@implementation MainVC

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.view.backgroundColor = [UIColor whiteColor];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated {
    _connection = [CGConnection connectionWithServiceType:@"test"];
    _connection.delegate = self;
    [_connection startConnection];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)connectionStarted:(CGConnection*)connection {
    NSLog(@"connectionStarted");
    [connection sendData:[@"Hello" dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)connection:(CGConnection*)connection cannotStartWithError:(NSError*)error {
    NSLog(@"connectionCannotStartWithError: %d", error.code);
}

- (void)connectionBrowserFoundNewService:(CGConnection*)connection {
    NSLog(@"browser found new service\n\nServices:\n%@", connection.services);
    [_connection makeConnectionToService:connection.services.firstObject];
}

- (void)connection:(CGConnection *)connection receivedData:(NSData *)data {
    NSLog(@"connectionReceivedData: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

@end
