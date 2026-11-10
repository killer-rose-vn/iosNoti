//
//  DetailViewController.h
//  Chi tiết 1 bản ghi: JSON đã gửi + response server + nút "Gửi lại".
//

#import <UIKit/UIKit.h>

@class ChargeRecord;

@interface DetailViewController : UIViewController

/// onResend được gọi sau khi bản ghi được cập nhật lại kết quả.
- (instancetype)initWithRecord:(ChargeRecord *)record
                      onResend:(void (^)(ChargeRecord *updated))onResend;

@end
