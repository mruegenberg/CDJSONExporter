//
//  CDJSONExporter.m
//  Classes
//
//  Created by Marcel Ruegenberg on 15.11.13.
//  Copyright (c) 2013 Dustlab. All rights reserved.
//

#import "CDJSONExporter.h"
#import <NSData+Base64/NSData+Base64.h>
#import "CodingValueTransformer.h"

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

+ (NSData *)exportContext:(NSManagedObjectContext *)context auxiliaryInfo:(NSDictionary *)auxiliary {
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
                fetchReq.includesSubentities = NO; // important
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
#warning Not yet supported in unpacking:
                            else if(attrType == NSBinaryDataAttributeType) {
                                NSData *dat = (NSData *)val;
                                NSString *klassName = [(NSAttributeDescription *)property attributeValueClassName];
                                if(klassName == nil) klassName = @"NSData"; // FIXME: not tested whether this is needed.
                                [attrs setValue:@{kValueKey:[dat base64EncodedString],
                                                  kClassKey:klassName}
                                         forKey:[property name]];
                            }
                            else if(attrType == NSTransformableAttributeType) {
                                NSValueTransformer *transformer = ({
                                    NSString *transformerName = [(NSAttributeDescription *)property valueTransformerName];
                                    (transformerName == nil ?
                                     [[CodingValueTransformer alloc] init] :
                                     [NSValueTransformer valueTransformerForName:transformerName]);
                                });
                                NSData *transformed = [transformer transformedValue:val];
                                
                                [attrs setValue:@{kValueKey:[transformed base64EncodedString]} // a dictionary as value without a value for kClassKey implies a transformed val
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
    
    for(NSString *key in auxiliary) {
        [data setObject:[auxiliary objectForKey:key] forKey:[NSString stringWithFormat:@"_%@", key]];
    }
    
    return [NSJSONSerialization dataWithJSONObject:data options:0 error:nil]; // option for debugging: NSJSONWritingPrettyPrinted
}

+ (BOOL)importData:(NSData *)data toContext:(NSManagedObjectContext *)context clear:(BOOL)clearContext {
    // TODO: some kind of optional merge facility if `clearContext` == NO
    //       i.e we want to be able to merge items based on something different than object IDs
    
    // set an undo manager in order to be more resilient wrt errors
    [context setUndoManager:[[NSUndoManager alloc] init]];
    [context.undoManager beginUndoGrouping];
    
    NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
    NSManagedObjectModel *model = coordinator.managedObjectModel;
    
    BOOL ok = YES;
    NSError *err;
    
    // first, clear the context
    //    @try {
    {
        NSArray *entities = [model entities];
        for(NSEntityDescription *entity in entities) {
            @autoreleasepool {
                NSArray *allObjects = ({
                    NSFetchRequest *fetchReq = [NSFetchRequest fetchRequestWithEntityName:[entity name]];
                    [context executeFetchRequest:fetchReq error:nil];
                });
                
                for(NSManagedObject *obj in allObjects) {
                    [context deleteObject:obj];
                }
                
                // TODO: find a way to save after each entity.
                //            ok = [context save:&err];
                //            if(! ok) break;
                //            [context reset]; // clear memory
            }
        }
        
        ok = [context save:&err];
        
        if(! ok) {
            [context reset];
            return NO;
        }
        
        NSDictionary *decodedJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            
#ifdef DEBUG
        // include extra resilience wrt problems in exported file?
#define EXTRA_RESILIENCE 1
#endif
        
        // first, decode the objects, and obtain permanent object IDs for them (as well as a mapping from import IDs
        // to permanent IDs
        NSMutableDictionary *importIDsToObjs = [NSMutableDictionary dictionaryWithCapacity:([entities count] * 30)];
        for(NSEntityDescription *entity in entities) {
            @autoreleasepool {
                NSArray *jsonItems = [decodedJSON objectForKey:[entity name]];
                NSUInteger c = [jsonItems count];
                NSMutableArray *objs = [NSMutableArray arrayWithCapacity:c];
                
                for(NSUInteger i=0; i < c; ++i) {
#ifdef EXTRA_RESILIENCE
                    NSDictionary *jsonItem = [jsonItems objectAtIndex:i];
                    NSString *entName = [[[jsonItem objectForKey:kObjectIDKey] pathComponents] objectAtIndex:1];
                    if([entName isEqualToString:[entity name]]) {
                        NSManagedObject *obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
                        [objs addObject:obj];
                    }
#else
                    NSManagedObject *obj = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
                    [objs addObject:obj];
#endif
                }
                
                [context obtainPermanentIDsForObjects:objs error:nil];
                
#ifdef EXTRA_RESILIENCE
                NSUInteger j = 0;
#endif
                for(NSUInteger i=0; i < c; ++i) {
                    NSDictionary *jsonItem = [jsonItems objectAtIndex:i];
#ifdef EXTRA_RESILIENCE
                    NSString *entName = [[[jsonItem objectForKey:kObjectIDKey] pathComponents] objectAtIndex:1];
                    if([entName isEqualToString:[entity name]]) {
                        NSString *objIDString = [jsonItem objectForKey:kObjectIDKey];
                        if([importIDsToObjs objectForKey:objIDString] != nil) {
                            // is the new entity a subentity of the one that is already there?
                            if([entity isKindOfEntity:[[importIDsToObjs objectForKey:objIDString] entity]]) {
                                [context deleteObject:[importIDsToObjs objectForKey:objIDString]]; // replace it
                                [importIDsToObjs setObject:[objs objectAtIndex:j] forKey:objIDString];
                                j++;
                            }
                        }
                        else {
                            [importIDsToObjs setObject:[objs objectAtIndex:j] forKey:objIDString];
                            j++;
                        }
                    }
#else
                    NSString *objIDString = [jsonItem objectForKey:kObjectIDKey];
                    [importIDsToObjs setObject:[objs objectAtIndex:i] forKey:objIDString];
#endif
                }
            }
        }
            
        for(NSEntityDescription *entity in entities) {
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
                            id val = [(NSDictionary *)attr objectForKey:kValueKey];
                            if([(NSDictionary *)attr objectForKey:kClassKey] == nil) {
                                NSData *dat = [NSData dataFromBase64String:((NSString *)val)];
                                NSAttributeDescription *attrDescr = (NSAttributeDescription *)[[entity attributesByName] objectForKey:attrName];
                                NSAssert([attrDescr attributeType] == NSTransformableAttributeType, @"Encoded data is not valid!");
                                NSValueTransformer *transformer = ({
                                    NSString *transformerName = [attrDescr valueTransformerName];
                                    (transformerName == nil ? [[CodingValueTransformer alloc] init] : [NSValueTransformer valueTransformerForName:transformerName]);
                                });
                                id decodedVal = [transformer reverseTransformedValue:dat];
                                [obj setValue:decodedVal forKey:attrName];
                            }
                            else if([[(NSDictionary *)attr objectForKey:kClassKey] isEqualToString:@"NSDate"]) {
                                NSDate *d = [NSDate dateWithTimeIntervalSinceReferenceDate:[(NSNumber *)val floatValue]];
                                [obj setValue:d forKey:attrName];
                            }
                            else if([[(NSDictionary *)attr objectForKey:kClassKey] isEqualToString:@"NSData"]) {
                                NSData *dat = [NSData dataFromBase64String:((NSString *)val)];
                                [obj setValue:dat forKey:attrName];
                            }
                        }
                        else {
                            [obj setValue:attr forKey:attrName];
                        }
                    }
                    
                    for(NSString *relationshipName in relations) {
                        id relation = [relations objectForKey:relationshipName];
                        if(relation != [NSNull null]) {
                            NSDictionary *relationDict = relation;
                            if([relationDict objectForKey:kItemKey] != nil) { // to-one relationship
                                NSString *targetItemObjID = [relationDict objectForKey:kItemKey];
                                [obj setValue:[importIDsToObjs objectForKey:targetItemObjID] forKey:relationshipName];
                            }
                            else {
                                if([[relationDict objectForKey:kEntityKey] isEqualToString:[entity name]]) {
                                    NSArray *relationItems = [relationDict objectForKey:kItemsKey];
                                    NSAssert(relationItems != nil, @"Missing target items");
                                    NSMutableSet *targetSet = [obj mutableSetValueForKey:relationshipName];
                                    for(NSString *targetItemObjID in relationItems) {
                                        id targetObject = [importIDsToObjs objectForKey:targetItemObjID];
                                        [targetSet addObject:targetObject];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        ok = [context save:nil];
        if(! ok) {
            [context reset];
            return NO;
        }
        
        [context.undoManager endUndoGrouping];
        context.undoManager = nil;
    }
    // catch all exceptions and restore the data store state to what it was before.
    // Note: this is one of the rare cases where catching all exceptions is a valid thing to do!
//    @catch (NSException *exception) {
//        [context.undoManager endUndoGrouping]; // we get there only if the previous block failed, and hence the undo grouping was not ended.
//        [context undo];
//    }
    
    return YES;
}

@end
