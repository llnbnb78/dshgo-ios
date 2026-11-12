#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface DSHWebViewController : UIViewController
@property (nonatomic, copy) void (^onClose)(void);
@end
