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

// `auxiliary`: a dictionary with values that are stored into the exported JSON as well.
//              all keys and values should be NSString objects.
+ (NSData *)exportContext:(NSManagedObjectContext *)context auxiliaryInfo:(NSDictionary *)auxiliary;

// import data.
// `clearContext`: Should the context be cleared before import?
// returns YES, if the import was successful and NO otherwise
+ (BOOL)importData:(NSData *)data toContext:(NSManagedObjectContext *)context clear:(BOOL)clearContext;

@end
