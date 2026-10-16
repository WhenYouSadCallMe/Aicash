//
//  CAComposerCameraCoordinator — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIImagePickerController;

@class UIViewController;

@interface CAComposerCameraCoordinator : NSObject
    - (signed long long)cameraAuthorizationStatus;
    - (id)cameraPicker;
    - (void)configureCameraPicker:(id)arg1;
    - (void)dismissCameraPicker:(id)arg1 completion:(id)arg2;
    - (void)finishWithFailure:(id)arg1;
    - (bool)finished;
    - (bool)finishing;
    - (void)imagePickerController:(id)arg1 didFinishPickingMediaWithInfo:(id)arg2;
    - (void)imagePickerControllerDidCancel:(id)arg1;
    - (bool)isCameraAvailable;
    - (id)newCameraPicker;
    - (id)onCapture;
    - (id)onDismiss;
    - (id)onFailure;
    - (double)openedAt;
    - (void)presentAuthorizedCamera;
    - (void)presentCameraPicker:(id)arg1 fromPresenter:(id)arg2;
    - (void)presentFromViewController:(id)arg1;
    - (UIViewController *)presenter;
    - (void)requestCameraAccess:(id)arg1;
    - (void)setCameraPicker:(id)arg1;
    - (void)setFinished:(id)arg1;
    - (void)setFinishing:(id)arg1;
    - (void)setOnCapture:(id)arg1;
    - (void)setOnDismiss:(id)arg1;
    - (void)setOnFailure:(id)arg1;
    - (void)setOpenedAt:(id)arg1;
    - (void)setPresenter:(id)arg1;
    - (void)setStarted:(id)arg1;
    - (bool)started;

@end

NS_ASSUME_NONNULL_END
