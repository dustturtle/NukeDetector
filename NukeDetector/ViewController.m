//
//  ViewController.m
//  NukeDetector
//
//  Created by GuanZhenwei on 2018/5/28.
//  Copyright © 2018年 GuanZhenwei. All rights reserved.
//


#import "ViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Nudity.h"

@interface ViewController ()<UIImagePickerControllerDelegate, UINavigationControllerDelegate>
{
    UIImagePickerController *_imagePickerController;
}

@property (weak, nonatomic) IBOutlet UILabel *resultLabel;

@property (strong, nonatomic) UIImageView *imgView;

@end

@implementation ViewController
- (IBAction)getPhoto:(id)sender
{
    // 创建一个警告控制器
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选取图片" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    // 设置警告响应事件
    UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:@"拍照" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // 设置照片来源为相机
        _imagePickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        // 设置进入相机时使用前置或后置摄像头
        _imagePickerController.cameraDevice = UIImagePickerControllerCameraDeviceFront;
        // 展示选取照片控制器
        [self presentViewController:_imagePickerController animated:YES completion:^{}];
    }];
    UIAlertAction *photosAction = [UIAlertAction actionWithTitle:@"从相册选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        _imagePickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        [self presentViewController:_imagePickerController animated:YES completion:^{}];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
    }];
    // 判断是否支持相机
    if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
    {
        // 添加警告按钮
        [alert addAction:cameraAction];
    }
    [alert addAction:photosAction];
    [alert addAction:cancelAction];
    // 展示警告控制器
    [self presentViewController:alert animated:YES completion:nil];
}


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // setup
    _imagePickerController = [[UIImagePickerController alloc] init];
    _imagePickerController.delegate = self;
    _imagePickerController.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    _imagePickerController.allowsEditing = YES;
    
    self.imgView = [[UIImageView alloc] initWithFrame:CGRectMake(30, 100, 224, 224)];
    [self.view addSubview:self.imgView];
}

- (UIImage *)normalizedImage:(UIImage *)image
{
    UIGraphicsBeginImageContext(CGSizeMake(224, 224));
    [image drawInRect:CGRectMake(0, 0, 224, 224)];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalizedImage;
}

- (CVPixelBufferRef)pixelBufferForNukeDFromImage:(UIImage *)image
{
    CGImageRef cgRef = image.CGImage;
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
    CVPixelBufferRef pxbuffer = NULL;
    
    // nukeD model要求224*224的输入！
    CGFloat frameWidth = 224.0;
    CGFloat frameHeight = 224.0;
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameWidth,
                                          frameHeight,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 frameWidth,
                                                 frameHeight,
                                                 8,
                                                 CVPixelBufferGetBytesPerRow(pxbuffer),
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    
    // gzw todo: 记录数据！ 1/2/3。
    //1.直接使用标准变换 CGContextConcatCTM(context, CGAffineTransformIdentity) = 不加任何变换
    //2.加上下面的三种变换： Rotation + flipVertical + flipHorizontal
    //3.注释掉flipHorizontal
    // 测试用pic A B C D..（默认取左上） 注：为避免不必要的问题，这里不把样本贴出。
    // pic A:纯黄图，上半身，无衣物
    // pic B:上半身，有胸罩，不能算严格的黄图
    // pic C:正常人物图，非黄
    // pic D:擦边球类型的性感图，取右上。
    // pic E:大概率认定为黄图，左侧有物体遮挡。
    // results:(A/B/C/D/E)
    // 1. 97.76黄/56.44黄/99.57正常/93.10黄/90.39黄
    // 2. 89.97黄/71.70黄/97.48正常/71.09黄/54.96正常
    // 3. 92.48黄/64.39黄/93.62正常/81.03黄/55.44正常
    //
    //结论：对于无疑的判例A和C，1的置信度更高，结果更可信;
    //对于判例B, 2和3更高概率认定为黄图，不理想;
    //对于判例D, 1的置信度更高（三种都认定其为黄图，取0.7的时候），我们认为也没有问题。
    //对于判例E, 输入的画面基本全裸体，1认定为黄图，另外两种认定为正常；1是最理想的。
    
    // 实验表明转换会降低精度。说明这里的输入应该不转换为宜。？？！！！
    // 不同的输入，不同的结果！
    
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0)); //0
    CGAffineTransform flipVertical = CGAffineTransformMake( 1, 0, 0, -1, 0, CGImageGetHeight(cgRef));
    CGContextConcatCTM(context, flipVertical);

//    CGAffineTransform flipHorizontal = CGAffineTransformMake( -1.0, 0.0, 0.0, 1.0, CGImageGetWidth(cgRef), 0.0);
//    CGContextConcatCTM(context, flipHorizontal);
    
    //gzw
    //CGContextConcatCTM(context, CGAffineTransformIdentity);
    
    CGContextDrawImage(context, CGRectMake(0,
                                           0,
                                           frameWidth,
                                           frameHeight),
                       cgRef);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (image)
    {
        Nudity *model = [[Nudity alloc] init];
        UIImage *normalizedImg = [self normalizedImage:image];
        self.imgView.image = normalizedImg;
        CVPixelBufferRef pbR = [self pixelBufferForNukeDFromImage:normalizedImg];
        NudityOutput *outPut = [model predictionFromData:pbR error:nil];
        NSDictionary *resultProb = outPut.prob;
        
        // refresh Label with result.
        if ([outPut.classLabel isEqualToString:@"SFW"])
        {
            // 结果为nsnumber，稍作处理一下！
            NSInteger resultValue = [resultProb[@"SFW"] doubleValue]*10000;
            float resultFloat = resultValue/100.0f;
            // 非裸露
            self.resultLabel.text = [NSString stringWithFormat:@"鉴定结果为正常，可信度达到%.2f%%", resultFloat];
        }
        else if ([outPut.classLabel isEqualToString:@"NSFW"])
        {
            // 结果为nsnumber，稍作处理一下！
            NSInteger resultValue = [resultProb[@"NSFW"] doubleValue]*10000;
            float resultFloat = resultValue/100.0f;
            // 裸露
            self.resultLabel.text = [NSString stringWithFormat:@"照片鉴定结果为黄图，可信度达到%.2f%%", resultFloat];
        }
        else
        {
            self.resultLabel.text = @"照片鉴定失败，出现未知错误";
        }
    }
    
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
