//
//  CDJSONExporter.h
//  Classes
//
//  Created by Marcel Ruegenberg on 15.11.13.
//  Copyright (c) 2013 Dustlab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface CDJSONExporter : NSObject

+ (CDJSONExporter *)sharedJSONExporter;

+ (NSData *)exportContext:(NSManagedObjectContext *)context;

// import data.
// `clearContext`: Should the context be cleared before import?
+ (void)importData:(NSData *)data toContext:(NSManagedObjectContext *)context clear:(BOOL)clearContext;

@end
