//
//  CDJSONExporter.m
//  Classes
//
//  Created by Marcel Ruegenberg on 15.11.13.
//  Copyright (c) 2013 Dustlab. All rights reserved.
//

#import "CDJSONExporter.h"

static NSString *kValueKey = @"Value";
static NSString *kClassKey = @"Class";

static NSString *kPropertyTypeRelationshipKey = @"Relationship";

static NSString *kEntityKey = @"Entity";
static NSString *kItemsKey = @"Items"; // for to-many relationships
static NSString *kItemKey = @"Item"; // for to-one     -"-

static NSString *kObjectIDKey = @"ObjectID";
static NSString *kAttrsKey = @"Attrs";
static NSString *kRelationshipsKey = @"Rels";

@implementation CDJSONExporter

+ (NSData *)exportContext:(NSManagedObjectContext *)context {
    // the exported data is a dictionary that maps from entity names to lists/arrays of exported objects.
    // each exported object maps property names to exported values.
    // exported values for most basic attributes are just whatever NSJSONSerialization does with them.
    // exported values for date attributes are mapped to dictionaries
    
    // TODO: do we actually need to store to-many relationships?
    //       not if all relationships have an inverse (as they should)
    //       in that case, it might also be possible to find a reconstruction ordering for the objects
    //       that doesn't require previous building of objects at all (or at least minimizes it),
    //       which can save memory when importing.
    
    NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
    NSManagedObjectModel *model = coordinator.managedObjectModel;
    
    NSArray *entitites = [model entities];
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithCapacity:[entitites count]];
    for(NSEntityDescription *entity in entitites) {
        @autoreleasepool {
            NSArray *properties = [entity properties];
            NSArray *allObjects = ({
                NSFetchRequest *fetchReq = [NSFetchRequest fetchRequestWithEntityName:[entity name]];
                [context executeFetchRequest:fetchReq error:nil];
            });
            NSMutableArray *items = [NSMutableArray arrayWithCapacity:[allObjects count]];
            for(NSManagedObject *obj in allObjects) {
                NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:[entity.attributesByName count]];
                NSMutableDictionary *relations = [NSMutableDictionary dictionaryWithCapacity:[entity.relationshipsByName count]];
                for(NSPropertyDescription *property in properties) {
                    // attributes
                    if([property isKindOfClass:[NSAttributeDescription class]]) {
                        // types that can be directly represented in JSON
                        NSAttributeType attrType = [(NSAttributeDescription *)property attributeType];
                        id val = [obj valueForKey:[property name]];
                        if(val == nil)
                            [attrs setValue:[NSNull null] forKey:[property name]];
                        else if(attrType < NSDateAttributeType) {
                            [attrs setValue:val forKey:[property name]];
                        }
                        // value type not directly representable in JSON
                        else {
                            if(attrType == NSDateAttributeType) {
                                NSDate *dateVal = (NSDate *)val;
                                [attrs setValue:@{kValueKey: [NSNumber numberWithInt:[dateVal timeIntervalSinceReferenceDate]],
                                                  kClassKey:[(NSAttributeDescription *)property attributeValueClassName]}
                                         forKey:[property name]];
                            }
                            else {
                                NSLog(@"WARNING: Can't serialize %@ value to JSON.", [(NSAttributeDescription *)property attributeValueClassName]);
                            }
                        }
                    }
                    // relantionships
                    else if([property isKindOfClass:[NSRelationshipDescription class]]) {
                        NSRelationshipDescription *relationship = (NSRelationshipDescription *)property;
                        if(! [relationship isToMany]) { // to-one
                            NSManagedObject *targetObject = [obj valueForKey:[property name]];
                            if(targetObject == nil) {
                                [relations setValue:[NSNull null] forKey:[property name]];
                            }
                            else {
                                NSManagedObjectID *objID = [targetObject objectID];
                                if([objID isTemporaryID]) {
                                    [context obtainPermanentIDsForObjects:@[targetObject] error:nil];
                                    objID = [obj objectID];
                                }
                                NSString *objIDString = [[objID URIRepresentation] path];
                                [relations setValue:@{kItemKey:objIDString,
                                                      kEntityKey:[[relationship destinationEntity] name]}
                                             forKey:[property name]];
                            }
                        }
                        else { // to-many
                            id<NSFastEnumeration> targetObjects = [obj valueForKey:[property name]];
                            {
                                NSMutableArray *tempObjects = [NSMutableArray array];
                                for(NSManagedObject *targetObject in targetObjects) {
                                    if([targetObject.objectID isTemporaryID])
                                        [tempObjects addObject:targetObject];
                                }
                                if([tempObjects count] > 0)
                                    [context obtainPermanentIDsForObjects:tempObjects error:nil];
                            }
                            NSMutableArray *targetItems = [NSMutableArray array];
                            for(NSManagedObject *targetObject in targetObjects) {
                                NSManagedObjectID *objID = [targetObject objectID];
                                NSString *objIDString = [[objID URIRepresentation] path];
                                [targetItems addObject:objIDString];
                            }
                            [relations setValue:@{kItemsKey:targetItems,
                                                  kEntityKey:[[relationship destinationEntity] name]}
                                         forKey:[property name]];
                        }
                    }
                }
                
                NSString *objIDString = ({
                    NSManagedObjectID *objID = [obj objectID];
                    if([objID isTemporaryID]) {
                        [context obtainPermanentIDsForObjects:@[obj] error:nil];
                        objID = [obj objectID];
                    }
                    [[objID URIRepresentation] path];
                });
                
                [items addObject:@{kObjectIDKey: objIDString,
                                   kAttrsKey: attrs,
                                   kRelationshipsKey: relations}];
            }
            
            [data setObject:items forKey:[entity name]];
            
            [context reset]; // save memory!
        }
    }
    return [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
}

+ (void)importData:(NSData *)data toContext:(NSManagedObjectContext *)context clear:(BOOL)clearContext {
    NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
    NSManagedObjectModel *model = coordinator.managedObjectModel;
    
    // first, clear the context
    NSArray *entitites = [model entities];
    for(NSEntityDescription *entity in entitites) {
        @autoreleasepool {
            NSArray *allObjects = ({
                NSFetchRequest *fetchReq = [NSFetchRequest fetchRequestWithEntityName:[entity name]];
                [context executeFetchRequest:fetchReq error:nil];
            });
            
            for(NSManagedObject *obj in allObjects) {
                [context deleteObject:obj];
            }
            
            [context save:NULL];
            [context reset]; // clear memory
        }
    }
    
    NSDictionary *decodedJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    // first, decode the objects, and obtain permanent object IDs for them (as well as a mapping from import IDs
    // to permanent IDs
    NSMutableDictionary *importIDsToObjs = [NSMutableDictionary dictionaryWithCapacity:([entitites count] * 30)];
    for(NSEntityDescription *entity in entitites) {
        @autoreleasepool {
            NSArray *jsonItems = [decodedJSON objectForKey:[entity name]];
            NSUInteger c = [jsonItems count];
            NSMutableArray *objs = [NSMutableArray arrayWithCapacity:c];
            
            for(NSUInteger i=0; i < c; ++i) {
                NSManagedObject *obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
                [objs addObject:obj];
            }
            
            [context obtainPermanentIDsForObjects:objs error:nil];
            
            for(NSUInteger i=0; i < c; ++i) {
                NSDictionary *jsonItem = [jsonItems objectAtIndex:i];
                NSString *objIDString = [jsonItem objectForKey:kObjectIDKey];
                [importIDsToObjs setObject:[objs objectAtIndex:i] forKey:objIDString];
            }
        }
    }
    
    for(NSEntityDescription *entity in entitites) {
        @autoreleasepool {
            NSArray *jsonItems = [decodedJSON objectForKey:[entity name]];
            for(NSDictionary *jsonItem in jsonItems) {
                NSString *objIDString   = [jsonItem objectForKey:kObjectIDKey];
                NSDictionary *attrs     = [jsonItem objectForKey:kAttrsKey];
                NSDictionary *relations = [jsonItem objectForKey:kRelationshipsKey];
                NSManagedObject *obj = [importIDsToObjs objectForKey:objIDString];
                
                for(NSString *attrName in attrs) {
                    id attr = [attrs objectForKey:attrName];
                    if(attr == [NSNull null]) {
                        [obj setValue:nil forKey:attrName];
                    }
                    else if([attr isKindOfClass:[NSDictionary class]]) {
                        NSNumber *val = [(NSDictionary *)attr objectForKey:kValueKey];
                        NSAssert([[(NSDictionary *)val objectForKey:kClassKey] isEqualToString:@"NSDate"], @"Wrong class in attribute!");
                        NSDate *d = [NSDate dateWithTimeIntervalSinceReferenceDate:[val floatValue]];
                        [obj setValue:d forKey:attrName];
                    }
                    else {
                        [obj setValue:attr forKey:attrName];
                    }
                }
                
                for(NSString *relationshipName in relations) {
                    NSDictionary *relation = [relations objectForKey:relationshipName];
                    if([relation objectForKey:kItemKey] != nil) { // to-one relationship
                        NSString *targetItemObjID = [relation objectForKey:kItemKey];
                        [obj setValue:[importIDsToObjs objectForKey:targetItemObjID] forKey:relationshipName];
                    }
                    else {
                        NSArray *relationItems = [relation objectForKey:kItemsKey];
                        NSAssert(relationItems != nil, @"Missing target items");
                        NSMutableSet *targetSet = [obj mutableSetValueForKey:relationshipName];
                        for(NSString *targetItemObjID in relationItems) {
                            [targetSet addObject:[importIDsToObjs objectForKey:targetItemObjID]];
                        }
                    }
                }
            }
        }
    }
    
    [context save:nil];
}

@end
