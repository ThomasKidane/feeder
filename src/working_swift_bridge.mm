//
//  working_swift_bridge.mm
//  feeder
//
//  Working Swift bridge using exact code from Swift app
//

#include "swift_device_controller.h"
#include <QTimer>
#include <QDebug>

// Import the working Swift code
#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>

// Working Swift bridge implementation
@interface WorkingSwiftBridge : NSObject <ICDeviceBrowserDelegate, ICCameraDeviceDownloadDelegate>

@property (nonatomic, strong) ICDeviceBrowser *deviceBrowser;
@property (nonatomic, strong) NSMutableArray<ICDevice*> *discoveredDevices;
@property (nonatomic, strong) ICCameraDevice *selectedCamera;
@property (nonatomic, assign) SwiftDeviceController *controller;

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
- (void)getFilesFromSelectedDevice;

@end

@implementation WorkingSwiftBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        self.discoveredDevices = [NSMutableArray array];
        [self setupDeviceBrowser];
    }
    return self;
}

- (void)setupDeviceBrowser {
    self.deviceBrowser = [[ICDeviceBrowser alloc] init];
    self.deviceBrowser.delegate = self;
    self.deviceBrowser.browsedDeviceTypeMask = ICDeviceTypeMaskCamera;
}

- (void)startDeviceDiscovery {
    [self.deviceBrowser start];
    NSLog(@"WorkingSwiftBridge: Started device discovery");
}

- (void)stopDeviceDiscovery {
    [self.deviceBrowser stop];
    NSLog(@"WorkingSwiftBridge: Stopped device discovery");
}

- (NSArray<NSString*>*)getDiscoveredDevices {
    return [self.discoveredDevices valueForKey:@"name"];
}

- (BOOL)selectDevice:(NSString*)deviceName {
    for (ICDevice *device in self.discoveredDevices) {
        if ([device.name isEqualToString:deviceName] && [device isKindOfClass:[ICCameraDevice class]]) {
            self.selectedCamera = (ICCameraDevice*)device;
            NSLog(@"WorkingSwiftBridge: Selected device: %@", deviceName);
            return YES;
        }
    }
    NSLog(@"WorkingSwiftBridge: Device not found: %@", deviceName);
    return NO;
}

- (NSArray<NSString*>*)getDeviceFiles {
    if (!self.selectedCamera) return @[];
    
    NSArray *mediaFiles = self.selectedCamera.mediaFiles;
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
    if (!self.selectedCamera) return NO;
    
    // Create subdirectory
    NSString *shortID = [self.selectedCamera.serialNumberString substringFromIndex:MAX(0, self.selectedCamera.serialNumberString.length - 4)] ?: @"Unknown";
    NSString *subdirectoryName = [NSString stringWithFormat:@"%@_%@", fileNamePrefix, shortID];
    NSURL *subdirectoryURL = [[NSURL fileURLWithPath:outputPath] URLByAppendingPathComponent:subdirectoryName];
    
    // Create directory
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtURL:subdirectoryURL 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&error];
    if (error) {
        NSLog(@"WorkingSwiftBridge: Failed to create directory: %@", error);
        return NO;
    }
    
    // Download selected files
    NSArray *mediaFiles = self.selectedCamera.mediaFiles;
    NSSet *selectedSet = [NSSet setWithArray:selectedFilenames];
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
        
        NSLog(@"WorkingSwiftBridge: Downloading selected file: %@ -> %@", file.name, finalName);
        
        [self.selectedCamera requestDownloadFile:file
                                       options:@{
                                           @"ICDownloadOptionDownloadsDirectoryURL": subdirectoryURL,
                                           @"ICDownloadOptionSaveAsFilename": finalName,
                                           @"ICDownloadOptionOverwrite": @YES
                                       }
                                downloadDelegate:self
                            didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:)
                                   contextInfo:nil];
    }
    
    return YES;
}

- (BOOL)downloadAllFiles:(NSString*)outputPath 
           fileNamePrefix:(NSString*)fileNamePrefix {
    if (!self.selectedCamera) return NO;
    
    // Create subdirectory
    NSString *shortID = [self.selectedCamera.serialNumberString substringFromIndex:MAX(0, self.selectedCamera.serialNumberString.length - 4)] ?: @"Unknown";
    NSString *subdirectoryName = [NSString stringWithFormat:@"%@_%@", fileNamePrefix, shortID];
    NSURL *subdirectoryURL = [[NSURL fileURLWithPath:outputPath] URLByAppendingPathComponent:subdirectoryName];
    
    // Create directory
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtURL:subdirectoryURL 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&error];
    if (error) {
        NSLog(@"WorkingSwiftBridge: Failed to create directory: %@", error);
        return NO;
    }
    
    // Download all files
    NSArray *mediaFiles = self.selectedCamera.mediaFiles;
    
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
        
        NSLog(@"WorkingSwiftBridge: Downloading file: %@ -> %@", originalName, finalName);
        
        [self.selectedCamera requestDownloadFile:file
                                       options:@{
                                           @"ICDownloadOptionDownloadsDirectoryURL": subdirectoryURL,
                                           @"ICDownloadOptionSaveAsFilename": finalName,
                                           @"ICDownloadOptionOverwrite": @YES
                                       }
                                downloadDelegate:self
                            didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:)
                                   contextInfo:nil];
    }
    
    return YES;
}

// ICDeviceBrowserDelegate methods
- (void)deviceBrowser:(ICDeviceBrowser*)browser didAddDevice:(ICDevice*)device moreComing:(BOOL)moreComing {
    [self.discoveredDevices addObject:device];
    NSLog(@"WorkingSwiftBridge: Discovered device: %@", device.name);
    
    // Emit signal to C++
    if (self.controller) {
        QString deviceName = QString::fromNSString(device.name);
        QMetaObject::invokeMethod(self.controller, "deviceConnected", Qt::QueuedConnection, 
                                Q_ARG(QString, deviceName));
    }
    
    // Auto-select the first device and get its files
    if (!self.selectedCamera && [device isKindOfClass:[ICCameraDevice class]]) {
        self.selectedCamera = (ICCameraDevice*)device;
        NSLog(@"WorkingSwiftBridge: Auto-selected device: %@", device.name);
        
        // Get files from the selected device
        [self getFilesFromSelectedDevice];
    }
}

- (void)deviceBrowser:(ICDeviceBrowser*)browser didRemoveDevice:(ICDevice*)device moreGoing:(BOOL)moreGoing {
    [self.discoveredDevices removeObject:device];
    NSLog(@"WorkingSwiftBridge: Removed device: %@", device.name);
    
    // Emit signal to C++
    if (self.controller) {
        QString deviceName = QString::fromNSString(device.name);
        QMetaObject::invokeMethod(self.controller, "deviceDisconnected", Qt::QueuedConnection, 
                                Q_ARG(QString, deviceName));
    }
}

// ICCameraDeviceDownloadDelegate methods
- (void)didDownloadFile:(ICCameraFile*)file error:(NSError*)error options:(NSDictionary*)options contextInfo:(void*)contextInfo {
    if (error) {
        NSLog(@"WorkingSwiftBridge: Download failed: %@", error);
    } else {
        NSLog(@"WorkingSwiftBridge: Download successful: %@", file.name);
    }
}

- (void)getFilesFromSelectedDevice {
    if (!self.selectedCamera) {
        NSLog(@"WorkingSwiftBridge: No device selected");
        return;
    }
    
    NSLog(@"WorkingSwiftBridge: Getting files from selected device...");
    NSLog(@"WorkingSwiftBridge: Device state: %@", self.selectedCamera);
    NSLog(@"WorkingSwiftBridge: Device capabilities: %@", self.selectedCamera.capabilities);
    
    // Try to open session first
    [self.selectedCamera requestOpenSession];
    
    // Wait a bit for session to open
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"WorkingSwiftBridge: Checking media files after session open...");
        
        // Get media files from the camera
        NSArray *mediaFiles = self.selectedCamera.mediaFiles;
        if (!mediaFiles) {
            NSLog(@"WorkingSwiftBridge: No media files found - device may need to be unlocked/trusted");
            return;
        }
        
        NSLog(@"WorkingSwiftBridge: Found %lu files", (unsigned long)mediaFiles.count);
    
    // Extract filenames and sizes
    NSMutableArray *filenames = [NSMutableArray array];
    NSMutableArray *filesizes = [NSMutableArray array];
    for (id item in mediaFiles) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *file = (ICCameraFile*)item;
            if (file.name) {
                [filenames addObject:file.name];
                
                // Get file size
                NSString *sizeStr = @"Unknown";
                if (file.fileSize > 0) {
                    sizeStr = [NSString stringWithFormat:@"%lld", file.fileSize];
                }
                [filesizes addObject:sizeStr];
                
                NSLog(@"WorkingSwiftBridge: Found file: %@ (size: %@)", file.name, sizeStr);
            }
        }
    }
    
    // Emit file list to C++
    if (self.controller && filenames.count > 0) {
        QStringList fileList;
        QStringList sizeList;
        
        for (int i = 0; i < filenames.count; i++) {
            NSString *filename = [filenames objectAtIndex:i];
            NSString *filesize = [filesizes objectAtIndex:i];
            fileList.append(QString::fromNSString(filename));
            sizeList.append(QString::fromNSString(filesize));
        }
        
        QMetaObject::invokeMethod(self.controller, "fileListReady", Qt::QueuedConnection, 
                                Q_ARG(QStringList, fileList),
                                Q_ARG(QStringList, sizeList));
        
        NSLog(@"WorkingSwiftBridge: Emitted %lu files to C++", (unsigned long)filenames.count);
    }
    });
}

@end

// C++ implementation
class SwiftDeviceControllerPrivate {
public:
    WorkingSwiftBridge *bridge;
    SwiftDeviceController *controller;
    
    SwiftDeviceControllerPrivate(SwiftDeviceController *ctrl) : controller(ctrl) {
        bridge = [[WorkingSwiftBridge alloc] init];
        bridge.controller = controller;
    }
    
    ~SwiftDeviceControllerPrivate() {
        bridge = nil;
    }
};

SwiftDeviceController::SwiftDeviceController(QObject *parent) : QObject(parent) {
    d = new SwiftDeviceControllerPrivate(this);
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