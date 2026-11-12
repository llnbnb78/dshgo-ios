#import "DSHWebViewController.h"

// dsh web 在 guest 里监听 127.0.0.1:3080，iSH 把 socket 直接落到 iOS 本机，
// 所以这里用普通的 NSURLSession / WKWebView 就能连上。
static NSString *const kDSHURL = @"http://127.0.0.1:3080/";

@interface DSHWebViewController () <WKNavigationDelegate>
@end

@implementation DSHWebViewController {
    WKWebView *_web;
    UILabel *_hint;
    UIActivityIndicatorView *_spinner;
    UIButton *_retry;
    NSTimer *_poll;
    NSInteger _tries;
    BOOL _loaded;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    _web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    _web.translatesAutoresizingMaskIntoConstraints = NO;
    _web.navigationDelegate = self;
    _web.opaque = NO;
    _web.backgroundColor = [UIColor systemBackgroundColor];
    _web.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:_web];

    UIToolbar *bar = [UIToolbar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    UIBarButtonItem *term = [[UIBarButtonItem alloc] initWithTitle:@"终端"
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(openTerminal)];
    UIBarButtonItem *reload = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                            target:self
                                                                            action:@selector(reloadTapped)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil action:nil];
    bar.items = @[term, flex, reload];
    [self.view addSubview:bar];

    _hint = [UILabel new];
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 0;
    _hint.font = [UIFont systemFontOfSize:14];
    _hint.textColor = [UIColor secondaryLabelColor];
    _hint.text = @"正在等 dsh web 起来…\n首次启动要解压内置系统，大约 1–2 分钟";
    [self.view addSubview:_hint];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_spinner startAnimating];
    [self.view addSubview:_spinner];

    _retry = [UIButton buttonWithType:UIButtonTypeSystem];
    _retry.translatesAutoresizingMaskIntoConstraints = NO;
    [_retry setTitle:@"重试" forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reloadTapped) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [self.view addSubview:_retry];

    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:bar.topAnchor],

        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_hint.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:14],
        [_hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [_hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [_retry.topAnchor constraintEqualToAnchor:_hint.bottomAnchor constant:14],
        [_retry.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startPolling];
}

- (void)startPolling {
    if (_loaded) return;
    _tries = 0;
    [_poll invalidate];
    _poll = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}

- (void)tick {
    if (_loaded) { [_poll invalidate]; return; }
    _tries++;
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:kDSHURL]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:2];
    NSURLSessionDataTask *t = [NSURLSession.sharedSession dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err == nil && [(NSHTTPURLResponse *)resp statusCode] < 500) {
                [self loaded];
            } else if (self->_tries % 15 == 0) {
                self->_hint.text = @"dsh web 还没起来。\n点「终端」看看是不是首次解压还没跑完";
            }
        });
    }];
    [t resume];
}

- (void)loaded {
    if (_loaded) return;
    _loaded = YES;
    [_poll invalidate];
    _hint.hidden = YES;
    _spinner.hidden = YES;
    _retry.hidden = YES;
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kDSHURL]]];
}

- (void)reloadTapped {
    _hint.hidden = NO;
    _spinner.hidden = NO;
    _retry.hidden = YES;
    _loaded = NO;
    [self startPolling];
}

- (void)openTerminal {
    if (self.onClose) self.onClose();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    _hint.hidden = NO;
    _retry.hidden = NO;
    _hint.text = [NSString stringWithFormat:@"打不开 dsh web：%@", error.localizedDescription];
}

@end
