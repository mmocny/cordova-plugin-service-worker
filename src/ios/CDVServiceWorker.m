/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <Cordova/CDV.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "CDVServiceWorker.h"

NSString * const SERVICE_WORKER = @"service_worker";
NSString * const SERVICE_WORKER_ACTIVATED = @"ServiceWorkerActivated";
NSString * const SERVICE_WORKER_INSTALLED = @"ServiceWorkerInstalled";
NSString * const SERVICE_WORKER_SCRIPT_CHECKSUM = @"ServiceWorkerScriptChecksum";

@implementation CDVServiceWorker

@synthesize context=_context;

- (NSString *)hashForString:(NSString *)string
{
    return @"9";
}

- (void)pluginInitialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    Boolean serviceWorkerInstalled = [defaults boolForKey:SERVICE_WORKER_INSTALLED];
    Boolean serviceWorkerActivated = [defaults boolForKey:SERVICE_WORKER_ACTIVATED];
    NSString *serviceWorkerScriptChecksum = [defaults stringForKey:SERVICE_WORKER_SCRIPT_CHECKSUM];

    NSString *serviceWorkerScriptFilename = nil;
    if ([[self viewController] isKindOfClass:[CDVViewController class]]) {
        CDVViewController *vc = (CDVViewController *)[self viewController];
        NSMutableDictionary *settings = [vc settings];
        serviceWorkerScriptFilename = [settings objectForKey:SERVICE_WORKER];
    }
    if (serviceWorkerScriptFilename != nil) {
        NSString *serviceWorkerScriptRelativePath = [NSString stringWithFormat:@"www/%@", serviceWorkerScriptFilename];
        NSLog(@"ServiceWorker relative path: %@", serviceWorkerScriptRelativePath);
        NSString *serviceWorkerScript = [self readScriptAtRelativePath:serviceWorkerScriptRelativePath];
        if (serviceWorkerScript != nil) {
            if (![[self hashForString:serviceWorkerScript] isEqualToString:serviceWorkerScriptChecksum]) {
                serviceWorkerInstalled = NO;
                serviceWorkerActivated = NO;
                [defaults setBool:NO forKey:SERVICE_WORKER_INSTALLED];
                [defaults setBool:NO forKey:SERVICE_WORKER_ACTIVATED];
                [defaults setObject:[self hashForString:serviceWorkerScript] forKey:SERVICE_WORKER_SCRIPT_CHECKSUM];
            }
            [self createServiceWorkerFromScript:serviceWorkerScript];
            if (!serviceWorkerInstalled) {
                [self installServiceWorker];
                // TODO: Don't do this on exception. Wait for extended events to complete
                serviceWorkerInstalled = YES;
                [defaults setBool:YES forKey:SERVICE_WORKER_INSTALLED];
            }
            // TODO: Don't do this immediately. Wait for installation to complete
            if (!serviceWorkerActivated) {
                [self activateServiceWorker];
                // TODO: Don't do this on exception. Wait for extended events to complete
                serviceWorkerActivated = YES;
                [defaults setBool:YES forKey:SERVICE_WORKER_ACTIVATED];
            }
        }
    } else {
        NSLog(@"No service worker script defined");
    }
}

# pragma mark ServiceWorker Functions

- (void)registerServiceWorker:(CDVInvokedUrlCommand*)command
{
    // Extract the arguments.
    NSString *scriptUrl = [command argumentAtIndex:0];
    NSDictionary *options = [command argumentAtIndex:1];

    // Create the ServiceWorker.
    [self createServiceWorkerFromFile:scriptUrl];
}

- (void)installServiceWorker
{
    [[self context] evaluateScript:@"this.oninstall && (typeof oninstall === 'function') && oninstall()"];
}

- (void)activateServiceWorker
{
    [[self context] evaluateScript:@"this.onactivate && (typeof onactivate === 'function') && onactivate()"];
}

# pragma mark Helper Functions

- (void)createServiceWorkerFromFile:(NSString *)filename
{
    // Read the ServiceWorker script.
    NSString *serviceWorkerScript = [self readScriptAtRelativePath:[NSString stringWithFormat:@"www/%@", filename]];

    // Create the ServiceWorker using this script.
    [self createServiceWorkerFromScript:serviceWorkerScript];
}

- (void)createServiceWorkerFromScript:(NSString *)script
{
    // Create a JS context.
    JSContext *context = [JSContext new];

    // Pipe JS logging in this context to NSLog.
    // NOTE: Not the nicest of hacks, but useful!
    [context evaluateScript:@"var console = {}"];
    context[@"console"][@"log"] = ^(NSString *message) {
        NSLog(@"JS log: %@", message);
    };

    // Load the required polyfills.
    [self loadPolyfillsIntoContext:context];

    // Load the service worker script.
    [self loadScript:script intoContext:context];

    // Save the JS context.
    [self setContext:context];
}

- (NSString *)readScriptAtRelativePath:(NSString*)relativePath
{
    // NOTE: Relative path means relative to the app bundle.

    // Compose the absolute path.
    NSString *absolutePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingString:[NSString stringWithFormat:@"/%@", relativePath]];

    // Read the script from the file.
    NSError *error;
    NSString *script = [NSString stringWithContentsOfFile:absolutePath encoding:NSUTF8StringEncoding error:&error];

    // If there was an error, log it and return.
    if (error) {
        NSLog(@"Could not read script: %@", [error description]);
        return nil;
    }

    // Return our script!
    return script;
}

- (void)loadPolyfillsIntoContext:(JSContext *)context
{
    // Specify the polyfill directory.
    // TODO: Move polyfills up one directory, so they're not in www.
    NSString *polyfillDirectoryPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingString:@"/www/polyfills"];

    // Get the list of polyfills.
    NSArray *polyfillFilenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:polyfillDirectoryPath error:NULL];

    // Read and load each polyfill.
    for (NSString *polyfillFilename in polyfillFilenames) {
        NSString *relativePath = [NSString stringWithFormat:@"www/polyfills/%@", polyfillFilename];
        [self readAndLoadScriptAtRelativePath:relativePath intoContext:context];
    }
}

- (void)loadScript:(NSString *)script intoContext:(JSContext *)context
{
    // Evaluate the script.
    [context evaluateScript:script];
}

- (void)readAndLoadScriptAtRelativePath:(NSString *)relativePath intoContext:(JSContext *)context
{
    // Read the script.
    NSString *script = [self readScriptAtRelativePath:relativePath];

    if (script == nil) {
        return;
    }

    // Load the script into the context.
    [self loadScript:script intoContext:context];
}

@end

