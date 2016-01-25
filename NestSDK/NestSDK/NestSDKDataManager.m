// Copyright (c) 2016 Petro Akzhygitov <petro.akzhygitov@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <JSONModel/JSONModel.h>
#import <NestSDK/NestSDKDataManager.h>
#import <NestSDK/NestSDKMetadataDataModel.h>
#import <NestSDK/NestSDKApplicationDelegate.h>
#import <NestSDK/NestSDKError.h>
#import <NestSDK/NestSDKStructureDataModel.h>
#import <NestSDK/NestSDKThermostatDataModel.h>
#import <NestSDK/NestSDKSmokeCOAlarmDataModel.h>
#import <NestSDK/NestSDKCameraDataModel.h>
#import <NestSDK/NestSDKDataManagerHelper.h>
#import <NestSDK/NestSDKMacroses.h>

#pragma mark const

static NSString *const kArgumentNameResult = @"result";

#pragma mark typedef

typedef void (^NestSDKDataUpdateHandler)(id, NSError *);


@interface NestSDKDataManager ()

@property(nonatomic, readonly) id <NestSDKService> service;

@end


@implementation NestSDKDataManager
#pragma mark Private

- (void) _dataModelWithURL:(NSString *)url block:(NestSDKDataUpdateHandler)block {
    @weakify(self)
    [self.service valuesForURL:url withBlock:^(id result, NSError *error) {
        @strongify(self)
        if (!self) return;

        [self _handleResult:result withURL:url block:block error:error];
    }];
}

- (NestSDKObserverHandle)_observeDataModelWithURL:(NSString *)url block:(NestSDKDataUpdateHandler)block {
    @weakify(self)
    return [self.service observeValuesForURL:url withBlock:^(id result, NSError *error) {
        @strongify(self)
        if (!self) return;

        [self _handleResult:result withURL:url block:block error:error];
    }];
}

- (void)_setDataModel:(id <NestSDKDataModelProtocol>)dataModel forURL:(NSString *)url block:(NestSDKDataUpdateHandler)block {
    NSDictionary *valuesDictionary = [(NestSDKDataModel *) dataModel toWritableDataModelDictionary];

    @weakify(self)
    [self.service setValues:valuesDictionary forURL:url withBlock:^(id result, NSError *error) {
        @strongify(self)
        if (!self) return;

        [self _handleResult:result withURL:url block:block error:error];
    }];
}

- (void)_handleResult:(id)result withURL:(NSString *)url block:(NestSDKDataUpdateHandler)block error:(NSError *)error {
    NSError *resultError = [self _errorInResult:result orError:error];
    if (resultError) {
        [self _returnError:resultError toBlock:block];
        return;
    }

    NSError *parseError;
    id dataModel = [self _parseDataModelWithURL:url fromData:result error:&parseError];

    if (parseError) {
        [self _returnParseError:parseError toBlock:block];
        return;
    }

    [self _returnDataModel:dataModel toBlock:block];
}

- (NSError *)_errorInResult:(id)result orError:(NSError *)error {
    if (error) return error;

    if (![result isKindOfClass:[NSDictionary class]]) {
        return [NestSDKError unexpectedArgumentTypeErrorWithName:kArgumentNameResult message:nil];
    }

    return nil;
}

- (id)_parseDataModelWithURL:(NSString *)url fromData:(id)data error:(NSError **)parseError {
    Class dataModelClass = [NestSDKDataManagerHelper dataModelClassWithURL:url];

    if ([self _shouldParseDataModelAsArrayWithURL:url]) {
        return [self _parseDataModelArrayWithClass:dataModelClass fromData:data error:parseError];

    } else {
        return [self _parseDataModelWithClass:dataModelClass fromData:data error:parseError];
    }
}

- (BOOL)_shouldParseDataModelAsArrayWithURL:(NSString *)url {
    return [url isEqualToString:[NestSDKDataManagerHelper structuresURL]];
}

- (NSArray *)_parseDataModelArrayWithClass:(Class)dataModelClass fromData:(id)result error:(NSError **)error {
    NSDictionary *resultDictionary = (NSDictionary *) result;
    NSMutableArray *dataModelsArray = [[NSMutableArray alloc] initWithCapacity:resultDictionary.count];

    for (NSDictionary *dictionary in resultDictionary.allValues) {
        id dataModelInArray = [(JSONModel *) [dataModelClass alloc] initWithDictionary:dictionary error:error];
        if ((*error)) return nil;

        [dataModelsArray addObject:dataModelInArray];
    }

    return dataModelsArray;
}

- (NestSDKDataModel *)_parseDataModelWithClass:(Class)dataModelClass fromData:(id)result error:(NSError **)error {
    return [(NestSDKDataModel *) [dataModelClass alloc] initWithDictionary:result error:error];
}

- (void)_returnParseError:(NSError *)parseError toBlock:(NestSDKDataUpdateHandler)block {
    NSError *error = [self _parseErrorWithUnderlyingError:parseError];
    [self _returnError:error toBlock:block];
}

- (NSError *)_parseErrorWithUnderlyingError:(NSError *)error {
    return error ? [NestSDKError unableToParseDataErrorWithUnderlyingError:error] : nil;
}

- (void)_returnError:(NSError *)error toBlock:(NestSDKDataUpdateHandler)block {
    block(nil, error);
}

- (void)_returnDataModel:(id)dataModel toBlock:(NestSDKDataUpdateHandler)block {
    block(dataModel, nil);
}

#pragma mark Override

- (id <NestSDKService>)service {
    return [NestSDKApplicationDelegate service];
}

#pragma mark Public

- (void)metadataWithBlock:(NestSDKMetadataUpdateHandler)block {
    NSString *metadataURL = [NestSDKDataManagerHelper metadataURL];
    [self _dataModelWithURL:metadataURL block:block];
}


- (void)structuresWithBlock:(NestSDKStructuresArrayUpdateHandler)block {
    NSString *structuresURL = [NestSDKDataManagerHelper structuresURL];
    [self _dataModelWithURL:structuresURL block:block];
}

- (NestSDKObserverHandle)observeStructuresWithBlock:(NestSDKStructuresArrayUpdateHandler)block {
    NSString *structuresURL = [NestSDKDataManagerHelper structuresURL];
    return [self _observeDataModelWithURL:structuresURL block:block];
}

- (void)setStructure:(id <NestSDKStructure>)structure block:(NestSDKStructureUpdateHandler)block {
    NSString *structureURL = [NestSDKDataManagerHelper structureURLWithStructureId:structure.structureId];
    [self _setDataModel:structure forURL:structureURL block:block];
}


- (void)thermostatWithId:(NSString *)thermostatId block:(NestSDKThermostatUpdateHandler)block {
    NSString *thermostatURL = [NestSDKDataManagerHelper thermostatURLWithThermostatId:thermostatId];
    [self _dataModelWithURL:thermostatURL block:block];
}

- (NestSDKObserverHandle)observeThermostatWithId:(NSString *)thermostatId block:(NestSDKThermostatUpdateHandler)block {
    NSString *thermostatURL = [NestSDKDataManagerHelper thermostatURLWithThermostatId:thermostatId];
    return [self _observeDataModelWithURL:thermostatURL block:block];
}

- (void)setThermostat:(id <NestSDKThermostat>)thermostat block:(NestSDKThermostatUpdateHandler)block {
    NSString *thermostatURL = [NestSDKDataManagerHelper thermostatURLWithThermostatId:thermostat.deviceId];
    [self _setDataModel:thermostat forURL:thermostatURL block:block];
}


- (void)smokeCOAlarmWithId:(NSString *)smokeCOAlarmId block:(NestSDKSmokeCOAlarmUpdateHandler)block {
    NSString *smokeCOAlarmURL = [NestSDKDataManagerHelper smokeCOAlarmURLWithSmokeCOAlarmId:smokeCOAlarmId];
    [self _dataModelWithURL:smokeCOAlarmURL block:block];
}

- (NestSDKObserverHandle)observeSmokeCOAlarmWithId:(NSString *)smokeCOAlarmId block:(NestSDKSmokeCOAlarmUpdateHandler)block {
    NSString *smokeCOAlarmURL = [NestSDKDataManagerHelper smokeCOAlarmURLWithSmokeCOAlarmId:smokeCOAlarmId];
    return [self _observeDataModelWithURL:smokeCOAlarmURL block:block];
}

- (void)setSmokeCOAlarm:(NestSDKSmokeCOAlarmDataModel *)smokeCOAlarm block:(NestSDKSmokeCOAlarmUpdateHandler)block {
    NSString *smokeCOAlarmURL = [NestSDKDataManagerHelper smokeCOAlarmURLWithSmokeCOAlarmId:smokeCOAlarm.deviceId];
    [self _setDataModel:smokeCOAlarm forURL:smokeCOAlarmURL block:block];
}


- (void)cameraWithId:(NSString *)cameraId block:(NestSDKCameraUpdateHandler)block {
    NSString *cameraURL = [NestSDKDataManagerHelper cameraURLWithCameraId:cameraId];
    [self _dataModelWithURL:cameraURL block:block];
}

- (void)setCamera:(NestSDKCameraDataModel *)camera block:(NestSDKCameraUpdateHandler)block {
    NSString *cameraURL = [NestSDKDataManagerHelper cameraURLWithCameraId:camera.deviceId];
    [self _setDataModel:camera forURL:cameraURL block:block];
}

- (NestSDKObserverHandle)observeCameraWithId:(NSString *)cameraId block:(NestSDKCameraUpdateHandler)block {
    NSString *cameraURL = [NestSDKDataManagerHelper cameraURLWithCameraId:cameraId];
    return [self _observeDataModelWithURL:cameraURL block:block];
}


- (void)removeObserverWithHandle:(NestSDKObserverHandle)handle {
    [self.service removeObserverWithHandle:handle];
}

- (void)removeAllObservers {
    [self.service removeAllObservers];
}

@end