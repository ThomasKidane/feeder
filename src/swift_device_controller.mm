//
//  swift_device_controller.mm
//  feeder
//
//  Objective-C++ bridge implementation for Swift integration
//

#include "swift_device_controller.h"
#include <QTimer>
#include <QDebug>

// Import the working Swift code
#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>

// Swift interface (we'll implement this in Swift)
@interface FeederSwiftBridge : NSObject <ICDeviceBrowserDelegate>

- (void)startDeviceDiscovery;
- (void)stopDeviceDiscovery;
- (NSArray<NSString*>*)getDiscoveredDevices;
- (BOOL)selectDevice:(NSString*)deviceName;
- (NSArray<NSString*>*)getDeviceFiles;
- (BOOL)downloadSelectedFiles:(NSString*)outputPath 
                fileNamePrefix:(NSString*)fileNamePrefix 
              selectedFilenames:(NSArray<NSString*>*)selectedFilenames;
- (BOOL)downloadAllFiles:(NSString*)outputPath 
           fileNamePrefix:(NSString*)fileNamePrefix;

@end

// Implementation of the Swift bridge
@implementation FeederSwiftBridge {
    ICDeviceBrowser *_deviceBrowser;
    NSMutableArray<ICDevice*> *_discoveredDevices;
    ICCameraDevice *_selectedCamera;
    id _downloadDelegate;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredDevices = [NSMutableArray array];
        [self setupDeviceBrowser];
    }
    return self;
}

- (void)setupDeviceBrowser {
    _deviceBrowser = [[ICDeviceBrowser alloc] init];
    _deviceBrowser.delegate = self;
    
    _deviceBrowser.browsedDeviceTypeMask = ICDeviceTypeMask.camera;
}

- (void)startDeviceDiscovery {
    [_deviceBrowser start];
    NSLog(@"FeederSwiftBridge: Started device discovery");
}

- (void)stopDeviceDiscovery {
    [_deviceBrowser stop];
    NSLog(@"FeederSwiftBridge: Stopped device discovery");
}

- (NSArray<NSString*>*)getDiscoveredDevices {
    return [_discoveredDevices valueForKey:@"name"];
}

- (BOOL)selectDevice:(NSString*)deviceName {
    for (ICDevice *device in _discoveredDevices) {
        if ([device.name isEqualToString:deviceName] && [device isKindOfClass:[ICCameraDevice class]]) {
            _selectedCamera = (ICCameraDevice*)device;
            NSLog(@"FeederSwiftBridge: Selected device: %@", deviceName);
            return YES;
        }
    }
    NSLog(@"FeederSwiftBridge: Device not found: %@", deviceName);
    return NO;
}

- (NSArray<NSString*>*)getDeviceFiles {
    if (!_selectedCamera) return @[];
    
    NSArray *mediaFiles = _selectedCamera.mediaFiles;
    NSMutableArray *fileNames = [NSMutableArray array];
    
    for (id item in mediaFiles) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *file = (ICCameraFile*)item;
            if (file.name) {
                [fileNames addObject:file.name];
            }
        }
    }
    
    return fileNames;
}

- (BOOL)downloadSelectedFiles:(NSString*)outputPath 
                fileNamePrefix:(NSString*)fileNamePrefix 
              selectedFilenames:(NSArray<NSString*>*)selectedFilenames {
    if (!_selectedCamera) return NO;
    
    // Create download delegate
    _downloadDelegate = [[FeederDownloadDelegate alloc] init];
    
    // Create subdirectory
    NSString *shortID = [_selectedCamera.serialNumberString substringFromIndex:MAX(0, _selectedCamera.serialNumberString.length - 4)] ?: @"Unknown";
    NSString *subdirectoryName = [NSString stringWithFormat:@"%@_%@", fileNamePrefix, shortID];
    NSURL *subdirectoryURL = [NSURL fileURLWithPath:outputPath].URLByAppendingPathComponent(subdirectoryName);
    
    // Create directory
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtURL:subdirectoryURL 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&error];
    if (error) {
        NSLog(@"FeederSwiftBridge: Failed to create directory: %@", error);
        return NO;
    }
    
    // Download selected files
    NSArray *mediaFiles = _selectedCamera.mediaFiles;
    NSMutableSet *selectedSet = [NSSet setWithArray:selectedFilenames];
    int selectedIndex = 0;
    
    for (id item in mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        
        ICCameraFile *file = (ICCameraFile*)item;
        if (!file.name || ![selectedSet containsObject:file.name]) continue;
        
        selectedIndex++;
        NSString *fileExtension = [file.name pathExtension];
        
        NSArray *imageExtensions = @[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"tif", @"tiff"];
        NSArray *videoExtensions = @[@"mov", @"mp4", @"m4v", @"avi"];
        
        NSString *typePrefix = @"_FILE_";
        if ([imageExtensions containsObject:[fileExtension lowercaseString]]) {
            typePrefix = @"_IMG_";
        } else if ([videoExtensions containsObject:[fileExtension lowercaseString]]) {
            typePrefix = @"_VID_";
        }
        
        NSString *fileNumber = [NSString stringWithFormat:@"%04d", selectedIndex];
        NSString *finalName = [NSString stringWithFormat:@"%@%@%@.%@", fileNamePrefix, typePrefix, fileNumber, fileExtension];
        
        NSLog(@"FeederSwiftBridge: Downloading selected file: %@ -> %@", file.name, finalName);
        
        [_selectedCamera requestDownloadFile:file
                                   options:@{
                                       ICDownloadOption.downloadsDirectoryURL: subdirectoryURL,
                                       ICDownloadOption.saveAsFilename: finalName,
                                       ICDownloadOption.overwrite: @YES
                                   }
                            downloadDelegate:_downloadDelegate
                        didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:)
                               contextInfo:nil];
    }
    
    return YES;
}

- (BOOL)downloadAllFiles:(NSString*)outputPath 
           fileNamePrefix:(NSString*)fileNamePrefix {
    if (!_selectedCamera) return NO;
    
    // Create download delegate
    _downloadDelegate = [[FeederDownloadDelegate alloc] init];
    
    // Create subdirectory
    NSString *shortID = [_selectedCamera.serialNumberString substringFromIndex:MAX(0, _selectedCamera.serialNumberString.length - 4)] ?: @"Unknown";
    NSString *subdirectoryName = [NSString stringWithFormat:@"%@_%@", fileNamePrefix, shortID];
    NSURL *subdirectoryURL = [NSURL fileURLWithPath:outputPath].URLByAppendingPathComponent(subdirectoryName);
    
    // Create directory
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtURL:subdirectoryURL 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&error];
    if (error) {
        NSLog(@"FeederSwiftBridge: Failed to create directory: %@", error);
        return NO;
    }
    
    // Download all files
    NSArray *mediaFiles = _selectedCamera.mediaFiles;
    
    for (int index = 0; index < mediaFiles.count; index++) {
        id item = mediaFiles[index];
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        
        ICCameraFile *file = (ICCameraFile*)item;
        NSString *originalName = file.name ?: @"file";
        NSString *fileExtension = [originalName pathExtension];
        
        NSArray *imageExtensions = @[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"tif", @"tiff"];
        NSArray *videoExtensions = @[@"mov", @"mp4", @"m4v", @"avi"];
        
        NSString *typePrefix = @"_FILE_";
        if ([imageExtensions containsObject:[fileExtension lowercaseString]]) {
            typePrefix = @"_IMG_";
        } else if ([videoExtensions containsObject:[fileExtension lowercaseString]]) {
            typePrefix = @"_VID_";
        }
        
        NSString *fileNumber = [NSString stringWithFormat:@"%04d", index + 1];
        NSString *finalName = [NSString stringWithFormat:@"%@%@%@.%@", fileNamePrefix, typePrefix, fileNumber, fileExtension];
        
        NSLog(@"FeederSwiftBridge: Downloading file: %@ -> %@", originalName, finalName);
        
        [_selectedCamera requestDownloadFile:file
                                   options:@{
                                       ICDownloadOption.downloadsDirectoryURL: subdirectoryURL,
                                       ICDownloadOption.saveAsFilename: finalName,
                                       ICDownloadOption.overwrite: @YES
                                   }
                            downloadDelegate:_downloadDelegate
                        didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:)
                               contextInfo:nil];
    }
    
    return YES;
}

@end

// Download delegate
@interface FeederDownloadDelegate : NSObject <ICCameraDeviceDownloadDelegate>
@end

@implementation FeederDownloadDelegate

- (void)didDownloadFile:(ICCameraFile*)file error:(NSError*)error options:(NSDictionary*)options contextInfo:(void*)contextInfo {
    if (error) {
        NSLog(@"FeederSwiftBridge: Download failed: %@", error);
    } else {
        NSLog(@"FeederSwiftBridge: Download successful: %@", file.name);
    }
}

@end

// C++ implementation
class SwiftDeviceControllerPrivate {
public:
    FeederSwiftBridge *bridge;
    
    SwiftDeviceControllerPrivate() {
        bridge = [[FeederSwiftBridge alloc] init];
    }
    
    ~SwiftDeviceControllerPrivate() {
        bridge = nil;
    }
};

SwiftDeviceController::SwiftDeviceController(QObject *parent) : QObject(parent) {
    d = new SwiftDeviceControllerPrivate();
}

SwiftDeviceController::~SwiftDeviceController() {
    delete d;
}

void SwiftDeviceController::startDeviceDiscovery() {
    [d->bridge startDeviceDiscovery];
}

void SwiftDeviceController::stopDeviceDiscovery() {
    [d->bridge stopDeviceDiscovery];
}

QStringList SwiftDeviceController::getDiscoveredDevices() {
    NSArray<NSString*> *devices = [d->bridge getDiscoveredDevices];
    QStringList result;
    
    for (NSString *device in devices) {
        result << QString::fromNSString(device);
    }
    
    return result;
}

bool SwiftDeviceController::selectDevice(const QString &deviceName) {
    return [d->bridge selectDevice:deviceName.toNSString()];
}

QStringList SwiftDeviceController::getDeviceFiles() {
    NSArray<NSString*> *files = [d->bridge getDeviceFiles];
    QStringList result;
    
    for (NSString *file in files) {
        result << QString::fromNSString(file);
    }
    
    return result;
}

bool SwiftDeviceController::downloadSelectedFiles(const QStringList &selectedFiles, 
                                                const QString &outputDirectory,
                                                const QString &fileNamePrefix) {
    NSMutableArray<NSString*> *files = [NSMutableArray array];
    for (const QString &file : selectedFiles) {
        [files addObject:file.toNSString()];
    }
    
    return [d->bridge downloadSelectedFiles:outputDirectory.toNSString()
                             fileNamePrefix:fileNamePrefix.toNSString()
                           selectedFilenames:files];
}

bool SwiftDeviceController::downloadAllFiles(const QString &outputDirectory,
                                           const QString &fileNamePrefix) {
    return [d->bridge downloadAllFiles:outputDirectory.toNSString()
                        fileNamePrefix:fileNamePrefix.toNSString()];
} 