CGConnection
============

Simple server/client to send data between Mac and iOS through the network

To Use
=============
Put ```CGConnection.h``` and ```CGConnection.m``` in your Xcode project and import the header

Make a connection like so:
```objc
CGConnection *connection = [CGConnection connectionWithServiceType:@"test"];
connection.delegate = self;
[connection startConnection];
```

Starting the connection makes the device visible to other devices searching for the same connection type. It also searches for other devices advertising.

To get a list of all the available devices, just access ```connection.services``` on the connection
To connect to a device (service), simply go ```[connection makeConnectionToService:service]```;

Data can be sent with ```[connection sendData:data]```
It can be received through the delegate method 
```- (void)connection:(CGConnection*)connection receivedData:(NSData*)data```

If you were to update a tableview with a list of available peers, everytime the client finds an advertising device, the delegate method ```- (void)connectionBrowserFoundNewService:(CGConnection*)connection``` is called

Take a look at the example project to see it in use.
