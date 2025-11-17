#import "WebSocketSupportPlugin.h"
#if __has_include(<web_socket_support/web_socket_support-Swift.h>)
#import <web_socket_support/web_socket_support-Swift.h>
#else
// Support local import with Swift Package Manager
#import "web_socket_support-Swift.h"
#endif

@implementation WebSocketSupportPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    [SwiftWebSocketSupportPlugin registerWithRegistrar:registrar];
}

@end