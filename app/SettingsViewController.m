//
//  SettingsViewController.m
//

#import "SettingsViewController.h"
#import "ConfigManager.h"
#import "SignatureHelper.h"
#import "NotificationPayloadBuilder.h"
#import "NotificationDispatcher.h"
#import "IosNotiDarwin.h"
#import "IosNotiLog.h"

typedef NS_ENUM(NSInteger, UIActionButtonStyle) {
    UIActionButtonStylePrimary,
    UIActionButtonStyleSecondary,
};

/// app_id dùng cho gói tin gửi thử (khớp payload mẫu trong tài liệu).
static NSString * const kTestAppID  = @"com.mo2pay.test";
static NSString * const kTestSender = @"[TEST] Thông báo thử nghiệm";
static NSString * const kTestMessage =
    @"Kiểm tra kết nối và tính hợp lệ của chữ ký từ iOS Jailbreak mpIosNotiReader";

@interface SettingsViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;

@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *simField;
@property (nonatomic, strong) UITextField *secretField;

@property (nonatomic, strong) UILabel *formulaLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *testButton;

// Khai báo trước để dùng trong buildViews (định nghĩa ở dưới).
- (void)buildViews;
- (UILabel *)sectionLabel:(NSString *)text;
- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder
                               secureText:(BOOL)secure
                             keyboardType:(UIKeyboardType)keyboardType
                                returnKey:(UIReturnKeyType)returnKey;
- (UIButton *)buttonWithTitle:(NSString *)title
                       action:(SEL)action
                        style:(UIActionButtonStyle)style;
- (NSString *)formulaText;
- (void)refreshSignaturePreview;
- (void)loadConfigIntoFields;
- (void)saveConfig;
- (void)sendTestPayload;
- (void)showAlertTitle:(NSString *)title message:(NSString *)message;
- (void)dismissKeyboard;
- (void)fieldChanged:(UITextField *)field;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cấu hình";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self buildViews];
    [self loadConfigIntoFields];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[ConfigManager sharedManager] reload];
    [self loadConfigIntoFields];
}

#pragma mark - UI

- (void)buildViews {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12;
    self.stackView.alignment = UIStackViewAlignmentFill;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];

    UILayoutGuide *guide = self.scrollView.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.stackView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-24],
    ]];

    // --- URL Server ---
    [self.stackView addArrangedSubview:[self sectionLabel:@"URL SERVER"]];
    self.urlField = [self textFieldWithPlaceholder:@"http://192.168.1.10:10007/api/MM/PutChargeNotify"
                                        secureText:NO
                                      keyboardType:UIKeyboardTypeURL
                                       returnKey:UIReturnKeyNext];
    [self.stackView addArrangedSubview:self.urlField];

    // --- SIM ---
    [self.stackView addArrangedSubview:[self sectionLabel:@"SIM (định danh máy)"]];
    self.simField = [self textFieldWithPlaceholder:@"bank_vietcombank|123"
                                        secureText:NO
                                      keyboardType:UIKeyboardTypeASCIICapable
                                       returnKey:UIReturnKeyNext];
    [self.stackView addArrangedSubview:self.simField];

    // --- Secret key ---
    [self.stackView addArrangedSubview:[self sectionLabel:@"Khóa bí mật (Secret Key)"]];
    self.secretField = [self textFieldWithPlaceholder:@"123456"
                                           secureText:YES
                                         keyboardType:UIKeyboardTypeASCIICapable
                                          returnKey:UIReturnKeyDone];
    [self.stackView addArrangedSubview:self.secretField];

    // --- Ghi chú công thức ---
    self.formulaLabel = [[UILabel alloc] init];
    self.formulaLabel.numberOfLines = 0;
    self.formulaLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.formulaLabel.textColor = [UIColor secondaryLabelColor];
    self.formulaLabel.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.formulaLabel.layer.cornerRadius = 10;
    self.formulaLabel.clipsToBounds = YES;
    self.formulaLabel.text = [self formulaText];
    [self.stackView addArrangedSubview:self.formulaLabel];

    // --- Preview chữ ký ---
    self.previewLabel = [[UILabel alloc] init];
    self.previewLabel.numberOfLines = 0;
    self.previewLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.previewLabel.textColor = [UIColor labelColor];
    [self.stackView addArrangedSubview:self.previewLabel];

    // --- Nút Lưu ---
    self.saveButton = [self buttonWithTitle:@"Lưu cấu hình"
                                     action:@selector(saveConfig)
                                      style:UIActionButtonStylePrimary];
    [self.stackView addArrangedSubview:self.saveButton];

    // --- Nút Gửi thử ---
    self.testButton = [self buttonWithTitle:@"Gửi thử dữ liệu lên Server"
                                     action:@selector(sendTestPayload)
                                      style:UIActionButtonStyleSecondary];
    [self.stackView addArrangedSubview:self.testButton];

    // --- Status ---
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.text = @"";
    [self.stackView addArrangedSubview:self.statusLabel];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = [text uppercaseString];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    label.textColor = [UIColor secondaryLabelColor];
    return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder
                               secureText:(BOOL)secure
                             keyboardType:(UIKeyboardType)keyboardType
                              returnKey:(UIReturnKeyType)returnKey {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.secureTextEntry = secure;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.keyboardType = keyboardType;
    field.returnKeyType = returnKey;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    field.delegate = self;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    [field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    return field;
}

- (UIButton *)buttonWithTitle:(NSString *)title
                       action:(SEL)action
                        style:(UIActionButtonStyle)style {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.layer.cornerRadius = 10;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;

    if (style == UIActionButtonStylePrimary) {
        button.backgroundColor = [UIColor systemBlueColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor tertiarySystemFillColor];
        [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Formula / preview

- (NSString *)formulaText {
    return
        @"  Signature = MD5_lowercase(\n"
        @"      app_id + \"|\" + id + \"|\" + time + \"|\" + sim + \"|\" + secret_key\n"
        @"  )\n"
        @"  - time: Unix milliseconds (vd 1793884666515)\n"
        @"  - sim: đúng giá trị ô SIM (đã chứa dấu \"|\")\n"
        @"  - đệm 2 dấu cách mỗi dòng để dễ copy";
}

- (void)refreshSignaturePreview {
    ConfigManager *config = [ConfigManager sharedManager];
    NSString *sim = self.simField.text.length > 0 ? self.simField.text : config.simID;
    NSString *secret = self.secretField.text.length > 0 ? self.secretField.text : config.secretKey;
    NSString *time = [SignatureHelper currentTimestampMillisecondsString];

    NSString *plain = [SignatureHelper plainTextWithAppID:kTestAppID
                                                       id:time
                                                     time:time
                                                      sim:sim
                                                secretKey:secret];
    NSString *md5 = [SignatureHelper md5Lowercase:plain];

    self.previewLabel.text = [NSString stringWithFormat:
        @"Plain mẫu:\n%@\n\nMD5:\n%@", plain, md5];
}

#pragma mark - Load / Save

- (void)loadConfigIntoFields {
    ConfigManager *config = [ConfigManager sharedManager];
    self.urlField.text = config.serverURL ?: @"";
    self.simField.text = config.simID ?: @"";
    self.secretField.text = config.secretKey ?: @"";
    [self refreshSignaturePreview];
}

- (void)saveConfig {
    [self dismissKeyboard];

    ConfigManager *config = [ConfigManager sharedManager];
    config.serverURL = self.urlField.text ?: @"";
    config.simID = self.simField.text ?: @"";
    config.secretKey = self.secretField.text ?: @"";

    if (![config isValidConfig]) {
        [self showAlertTitle:@"URL không hợp lệ"
                     message:@"URL phải bắt đầu bằng http:// hoặc https:// và có host."];
        return;
    }

    BOOL ok = [config save];

    // Báo Tweak đọc lại config ngay — không cần respring.
    IosNotiPostConfigChanged();

    self.statusLabel.text = ok
        ? [NSString stringWithFormat:@"Đã lưu lúc %@ — Tweak sẽ dùng ngay.",
           [NSDateFormatter localizedStringFromDate:[NSDate date]
                                          dateStyle:NSDateFormatterNoStyle
                                          timeStyle:NSDateFormatterMediumStyle]]
        : @"Không ghi được file cấu hình. Kiểm tra quyền thư mục Preferences.";
    self.statusLabel.textColor = ok ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    INLog(@"settings saved: %d", ok);
}

#pragma mark - Test send

- (void)sendTestPayload {
    [self dismissKeyboard];

    ConfigManager *config = [ConfigManager sharedManager];
    config.serverURL = self.urlField.text ?: config.serverURL;
    config.simID = self.simField.text ?: config.simID;
    config.secretKey = self.secretField.text ?: config.secretKey;

    if (![config isValidConfig]) {
        [self showAlertTitle:@"URL không hợp lệ" message:@"Kiểm tra lại URL Server rồi thử lại."];
        return;
    }
    // Lưu để tweak/app dùng cùng một cấu hình.
    [config save];

    NSString *time = [SignatureHelper currentTimestampMillisecondsString];
    NSDictionary *payload = [NotificationPayloadBuilder payloadWithAppID:kTestAppID
                                                                  sender:kTestSender
                                                                 message:kTestMessage
                                                                recordID:time
                                                                  timeMS:time];

    self.testButton.enabled = NO;
    [self.testButton setTitle:@"Đang gửi…" forState:UIControlStateNormal];
    self.statusLabel.text = @"Đang gửi gói tin thử…";
    self.statusLabel.textColor = [UIColor secondaryLabelColor];

    __weak typeof(self) weakSelf = self;
    [[NotificationDispatcher sharedDispatcher] submitPayload:payload
                                                 completion:^(NSInteger httpStatus,
                                                              NSString *responseBody,
                                                              NSInteger rowID,
                                                              BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.testButton.enabled = YES;
        [strongSelf.testButton setTitle:@"Gửi thử dữ liệu lên Server" forState:UIControlStateNormal];

        strongSelf.statusLabel.text = [NSString stringWithFormat:
            @"Lần gửi cuối: HTTP %ld — %@", (long)httpStatus,
            success ? @"thành công" : @"thất bại"];
        strongSelf.statusLabel.textColor = success ? [UIColor systemGreenColor] : [UIColor systemRedColor];

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:
                success ? [NSString stringWithFormat:@"Gửi thành công (HTTP %ld)", (long)httpStatus]
                        : [NSString stringWithFormat:@"Gửi thất bại (HTTP %ld)", (long)httpStatus]
                                            message:[NSString stringWithFormat:
                                                @"URL: %@\n\nSignature: %@\n\nServer trả về:\n%@",
                                                config.serverURL,
                                                payload[@"signature"],
                                                responseBody.length > 0 ? responseBody : @"(rỗng)"]
                                     preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [strongSelf presentViewController:alert animated:YES completion:nil];

        INLog(@"test send finished: status=%ld row=%ld", (long)httpStatus, (long)rowID);
    }];
}

#pragma mark - Helpers

- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)fieldChanged:(UITextField *)field {
    [self refreshSignaturePreview];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.urlField) {
        [self.simField becomeFirstResponder];
    } else if (textField == self.simField) {
        [self.secretField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

@end
