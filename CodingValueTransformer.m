//
//  NSCodingValueTransformer.m
//  Classes
//
//  Created by Marcel Ruegenberg on 21.11.13.
//  Copyright (c) 2013 Dustlab. All rights reserved.
//

#import "CodingValueTransformer.h"

@implementation CodingValueTransformer

- (id)transformedValue:(id)value {
    NSAssert([value conformsToProtocol:@protocol(NSCoding)], @"This transformer can onyl handle NSCoding-compliant objects.");
    
    NSData *dat = [NSKeyedArchiver archivedDataWithRootObject:value];
    
    return dat;
}

- (id)reverseTransformedValue:(id)value {
    return [NSKeyedUnarchiver unarchiveObjectWithData:value];
}

@end
