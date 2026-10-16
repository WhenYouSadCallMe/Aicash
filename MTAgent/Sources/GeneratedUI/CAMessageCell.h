//
//  CAMessageCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAMessageCell : UITableViewCell
    - (void)appendMarkdownBlock:(id)arg1 toStack:(id)arg2 isUser:(id)arg3;
    - (id)artifactForMarkdownTarget:(id)arg1;
    - (NSDictionary *)artifactLookup;
    - (NSLayoutConstraint *)assistantWidthConstraint;
    - (id)attachmentGridForMessage:(id)arg1;
    - (id)attachmentPathResolver;
    - (id)attributedStringForText:(id)arg1 isUser:(id)arg2;
    - (NSLayoutConstraint *)bodyBottomConstraint;
    - (NSLayoutConstraint *)bodyLeadingConstraint;
    - (UIStackView *)bodyStack;
    - (NSLayoutConstraint *)bodyTopConstraint;
    - (NSLayoutConstraint *)bodyTrailingConstraint;
    - (UIView *)bubbleView;
    - (void)commitPreparedBodyStack;
    - (void)configureWithMessage:(id)arg1;
    - (bool)configuredQueued;
    - (id)contextMenuInteraction:(id)arg1 configurationForMenuAtLocation:(id)arg2;
    - (unsigned long long)deferredBlockIndex;
    - (NSArray *)deferredBlocks;
    - (UIStackView *)deferredBodyStack;
    - (NSString *)deferredMessageID;
    - (unsigned long long)deferredRenderGeneration;
    - (void)handleSteerQueuedButton;
    - (CAMessageCell *)initWithFrame:(id)arg1;
    - (void)layoutSubviews;
    - (NSLayoutConstraint *)leadingConstraint;
    - (void)loadThumbnailAtPath:(id)arg1 pixelSize:(id)arg2 intoButton:(id)arg3;
    - (id)markdownImageFallbackForBlock:(id)arg1;
    - (id)messageContextMenu;
    - (id)onDeferredRenderStep;
    - (id)onEditQueued;
    - (id)onOpenAttachmentPath;
    - (id)onOpenMarkdownLink;
    - (id)onSelectText;
    - (id)onSteerQueued;
    - (id)onWithdrawQueued;
    - (id)parseMarkdownBlocks:(id)arg1;
    - (id)plainStreamingLabel;
    - (id)preferredLayoutAttributesFittingAttributes:(id)arg1;
    - (void)prepareForReuse;
    - (void)preparseMarkdownForMessage:(id)arg1 completion:(id)arg2;
    - (void)prewarmRichPreviewsForMessage:(id)arg1 completion:(id)arg2;
    - (CAShapeLayer *)queuedBorderLayer;
    - (id)queuedGuideViewWithTheme:(id)arg1;
    - (NSString *)rawCopyText;
    - (void)renderDeferredMarkdownBatchForGeneration:(id)arg1 isUser:(id)arg2;
    - (bool)renderingStreaming;
    - (void)resetStreamingViews;
    - (void)setArtifactLookup:(id)arg1;
    - (void)setAssistantWidthConstraint:(id)arg1;
    - (void)setAttachmentPathResolver:(id)arg1;
    - (void)setBodyBottomConstraint:(id)arg1;
    - (void)setBodyLeadingConstraint:(id)arg1;
    - (void)setBodyStack:(id)arg1;
    - (void)setBodyTopConstraint:(id)arg1;
    - (void)setBodyTrailingConstraint:(id)arg1;
    - (void)setBubbleView:(id)arg1;
    - (void)setConfiguredQueued:(id)arg1;
    - (void)setDeferredBlockIndex:(id)arg1;
    - (void)setDeferredBlocks:(id)arg1;
    - (void)setDeferredBodyStack:(id)arg1;
    - (void)setDeferredMessageID:(id)arg1;
    - (void)setDeferredRenderGeneration:(id)arg1;
    - (void)setLeadingConstraint:(id)arg1;
    - (void)setOnDeferredRenderStep:(id)arg1;
    - (void)setOnEditQueued:(id)arg1;
    - (void)setOnOpenAttachmentPath:(id)arg1;
    - (void)setOnOpenMarkdownLink:(id)arg1;
    - (void)setOnSelectText:(id)arg1;
    - (void)setOnSteerQueued:(id)arg1;
    - (void)setOnWithdrawQueued:(id)arg1;
    - (void)setQueuedBorderLayer:(id)arg1;
    - (void)setRawCopyText:(id)arg1;
    - (void)setRenderingStreaming:(id)arg1;
    - (void)setStreamingCommittedLength:(id)arg1;
    - (void)setStreamingTextLabel:(id)arg1;
    - (void)setTrailingConstraint:(id)arg1;
    - (unsigned long long)streamingCommittedLength;
    - (CAStreamingTextView *)streamingTextLabel;
    - (NSLayoutConstraint *)trailingConstraint;
    - (void)updateStreamingText:(id)arg1;

@end

NS_ASSUME_NONNULL_END
