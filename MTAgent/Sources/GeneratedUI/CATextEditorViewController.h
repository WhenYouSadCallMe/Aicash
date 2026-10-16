//
//  CATextEditorViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CATextEditorViewController : UIViewController
    - (id)displayPath;
    - (bool)editable;
    - (bool)fileExists;
    - (void)finish;
    - (void)handleCancel;
    - (void)handleCopy;
    - (void)handleSave;
    - (UIView *)infoBar;
    - (CATextEditorViewController *)initWithTitle:(id)arg1 path:(id)arg2 template:(id)arg3 editable:(id)arg4;
    - (bool)isDirty;
    - (void)loadFile;
    - (bool)loaded;
    - (NSString *)note;
    - (id)onSaved;
    - (NSString *)originalText;
    - (NSString *)path;
    - (UILabel *)pathLabel;
    - (bool)prefillTemplateWhenEmpty;
    - (UIBarButtonItem *)saveItem;
    - (bool)saving;
    - (void)setEditable:(id)arg1;
    - (void)setFileExists:(id)arg1;
    - (void)setInfoBar:(id)arg1;
    - (void)setLoaded:(id)arg1;
    - (void)setNote:(id)arg1;
    - (void)setOnSaved:(id)arg1;
    - (void)setOriginalText:(id)arg1;
    - (void)setPath:(id)arg1;
    - (void)setPathLabel:(id)arg1;
    - (void)setPrefillTemplateWhenEmpty:(id)arg1;
    - (void)setSaveItem:(id)arg1;
    - (void)setSaving:(id)arg1;
    - (void)setSpinner:(id)arg1;
    - (void)setStatusLabel:(id)arg1;
    - (void)setTemplateText:(id)arg1;
    - (void)setTextView:(id)arg1;
    - (UIActivityIndicatorView *)spinner;
    - (UILabel *)statusLabel;
    - (NSString *)templateText;
    - (UITextView *)textView;
    - (void)textViewDidChange:(id)arg1;
    - (void)themeDidChange;
    - (void)updateStatus;
    - (void)viewDidLoad;
    - (void)viewWillDisappear:(id)arg1;

@end

NS_ASSUME_NONNULL_END
