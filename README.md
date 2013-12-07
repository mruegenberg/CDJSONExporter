CDJSONExporter
==============

Conversion of a Core Data Store to/from JSON. The goal of this is to provide human-readable backup functionality for apps using Core Data without relying on any implementation details of Core Data.

Installation
------------
Installation with the CDJSONExporter [CocoaPod](http://cocoapods.org) is the recommended way. 

Otherwise, copy the code of `CDJSONExporter` (all `.h` and `.m` files in this repository) and [NSData+Base64](https://github.com/l4u/NSData-Base64) to your project.

Usage
-----
First, import: `#import "CDJSONExporter.h"`.

To create export data:

    NSData *export = [CDJSONExporter exportContext:appDelegate.managedObjectContext
                                     auxiliaryInfo:@{@"some key": someOptionalAuxiliaryInformation}];
                                     
This data can be written to a temporary file and shared with a `UIDocumentInteractionController` or used as an attachment in a mail compose view controller:

    MFMailComposeViewController *mailer = ...;
    // ...
    [mailer addAttachmentData:export mimeType:@"application/json" fileName:@"backup.someAppBackup"];
    
To open the data later, you need to register your app as a handler for a document type / UTI with the extension `someAppBackup`.
Afterwards, you can handle data with this extension in your app delegate:

    - (BOOL)application:(UIApplication *)application 
                openURL:(NSURL *)url 
      sourceApplication:(NSString *)sourceApplication 
             annotation:(id)annotation {
        if([[url pathExtension] isEqualToString:@"someAppBackup"]) {
            NSData *jsonData = [NSData dataWithContentsOfURL:url];
            BOOL success = [CDJSONExporter importData:jsonData toContext:appDelegate.managedObjectContext clear:YES];
            if([[NSFileManager defaultManager] isDeletableFileAtPath:[url path]])
                [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
        }
    }

Known Issues
------------
The memory use of this code is not optimal. The main reason is the inability of Core Data to ever save invalid objects. This is usually a good thing, but prevents the code from persisting changes while importing.

![Travis CI build status](https://api.travis-ci.org/mruegenberg/CDJSONExporter.png)
