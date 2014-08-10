//
//  ZFModalTransitionAnimator.m
//
//  Created by Amornchai Kanokpullwad on 5/10/14.
//  Copyright (c) 2014 zoonref. All rights reserved.
//

#import "ZFModalTransitionAnimator.h"
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
@import Accelerate;
#endif

@interface UIImage (ImageBlur)
- (UIImage *)applyBlurWithRadius:(CGFloat)blurRadius tintColor:(UIColor *)tintColor saturationDeltaFactor:(CGFloat)saturationDeltaFactor maskImage:(UIImage *)maskImage;
@end

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
@implementation UIImage (ImageBlur)
// This method is taken from Apple's UIImageEffects category provided in WWDC 2013 sample code
- (UIImage *)applyBlurWithRadius:(CGFloat)blurRadius tintColor:(UIColor *)tintColor saturationDeltaFactor:(CGFloat)saturationDeltaFactor maskImage:(UIImage *)maskImage
{
    // Check pre-conditions.
    if (self.size.width < 1 || self.size.height < 1) {
        NSLog (@"*** error: invalid size: (%.2f x %.2f). Both dimensions must be >= 1: %@", self.size.width, self.size.height, self);
        return nil;
    }
    if (!self.CGImage) {
        NSLog (@"*** error: image must be backed by a CGImage: %@", self);
        return nil;
    }
    if (maskImage && !maskImage.CGImage) {
        NSLog (@"*** error: maskImage must be backed by a CGImage: %@", maskImage);
        return nil;
    }
    
    CGRect imageRect = { CGPointZero, self.size };
    UIImage *effectImage = self;
    
    BOOL hasBlur = blurRadius > __FLT_EPSILON__;
    BOOL hasSaturationChange = fabs(saturationDeltaFactor - 1.) > __FLT_EPSILON__;
    if (hasBlur || hasSaturationChange) {
        UIGraphicsBeginImageContextWithOptions(self.size, NO, [[UIScreen mainScreen] scale]);
        CGContextRef effectInContext = UIGraphicsGetCurrentContext();
        CGContextScaleCTM(effectInContext, 1.0, -1.0);
        CGContextTranslateCTM(effectInContext, 0, -self.size.height);
        CGContextDrawImage(effectInContext, imageRect, self.CGImage);
        
        vImage_Buffer effectInBuffer;
        effectInBuffer.data     = CGBitmapContextGetData(effectInContext);
        effectInBuffer.width    = CGBitmapContextGetWidth(effectInContext);
        effectInBuffer.height   = CGBitmapContextGetHeight(effectInContext);
        effectInBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext);
        
        UIGraphicsBeginImageContextWithOptions(self.size, NO, [[UIScreen mainScreen] scale]);
        CGContextRef effectOutContext = UIGraphicsGetCurrentContext();
        vImage_Buffer effectOutBuffer;
        effectOutBuffer.data     = CGBitmapContextGetData(effectOutContext);
        effectOutBuffer.width    = CGBitmapContextGetWidth(effectOutContext);
        effectOutBuffer.height   = CGBitmapContextGetHeight(effectOutContext);
        effectOutBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext);
        
        if (hasBlur) {
            // A description of how to compute the box kernel width from the Gaussian
            // radius (aka standard deviation) appears in the SVG spec:
            // http://www.w3.org/TR/SVG/filters.html#feGaussianBlurElement
            //
            // For larger values of 's' (s >= 2.0), an approximation can be used: Three
            // successive box-blurs build a piece-wise quadratic convolution kernel, which
            // approximates the Gaussian kernel to within roughly 3%.
            //
            // let d = floor(s * 3*sqrt(2*pi)/4 + 0.5)
            //
            // ... if d is odd, use three box-blurs of size 'd', centered on the output pixel.
            //
            CGFloat inputRadius = blurRadius * [[UIScreen mainScreen] scale];
            NSUInteger radius = floor(inputRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
            if (radius % 2 != 1) {
                radius += 1; // force radius to be odd so that the three box-blur methodology works.
            }
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
        }
        BOOL effectImageBuffersAreSwapped = NO;
        if (hasSaturationChange) {
            CGFloat s = saturationDeltaFactor;
            CGFloat floatingPointSaturationMatrix[] = {
                0.0722 + 0.9278 * s,  0.0722 - 0.0722 * s,  0.0722 - 0.0722 * s,  0,
                0.7152 - 0.7152 * s,  0.7152 + 0.2848 * s,  0.7152 - 0.7152 * s,  0,
                0.2126 - 0.2126 * s,  0.2126 - 0.2126 * s,  0.2126 + 0.7873 * s,  0,
                0,                    0,                    0,  1,
            };
            const int32_t divisor = 256;
            NSUInteger matrixSize = sizeof(floatingPointSaturationMatrix)/sizeof(floatingPointSaturationMatrix[0]);
            int16_t saturationMatrix[matrixSize];
            for (NSUInteger i = 0; i < matrixSize; ++i) {
                saturationMatrix[i] = (int16_t)roundf(floatingPointSaturationMatrix[i] * divisor);
            }
            if (hasBlur) {
                vImageMatrixMultiply_ARGB8888(&effectOutBuffer, &effectInBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
                effectImageBuffersAreSwapped = YES;
            }
            else {
                vImageMatrixMultiply_ARGB8888(&effectInBuffer, &effectOutBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
            }
        }
        if (!effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        if (effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    // Set up output context.
    UIGraphicsBeginImageContextWithOptions(self.size, NO, [[UIScreen mainScreen] scale]);
    CGContextRef outputContext = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(outputContext, 1.0, -1.0);
    CGContextTranslateCTM(outputContext, 0, -self.size.height);
    
    // Draw base image.
    CGContextDrawImage(outputContext, imageRect, self.CGImage);
    
    // Draw effect image.
    if (hasBlur) {
        CGContextSaveGState(outputContext);
        if (maskImage) {
            CGContextClipToMask(outputContext, imageRect, maskImage.CGImage);
        }
        CGContextDrawImage(outputContext, imageRect, effectImage.CGImage);
        CGContextRestoreGState(outputContext);
    }
    
    // Add in color tint.
    if (tintColor) {
        CGContextSaveGState(outputContext);
        CGContextSetFillColorWithColor(outputContext, tintColor.CGColor);
        CGContextFillRect(outputContext, imageRect);
        CGContextRestoreGState(outputContext);
    }
    
    // Output image is ready.
    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return outputImage;
}
@end
#endif

@interface ZFModalTransitionAnimator ()
@property (nonatomic, strong) UIViewController *modalController;
@property (nonatomic, strong) ZFDetectScrollViewEndGestureRecognizer *gesture;
@property (nonatomic, strong) id<UIViewControllerContextTransitioning> transitionContext;
@property CGFloat panLocationStart;
@property BOOL isDismiss;
@property BOOL isInteractive;
@property CATransform3D tempTransform;
@property (nonatomic, strong) UITapGestureRecognizer *backgroundTap;
@end

@implementation ZFModalTransitionAnimator

- (instancetype)initWithModalViewController:(UIViewController *)modalViewController
{
    self = [super init];
    if (self) {
        _modalController = modalViewController;
        _direction = ZFModalTransitonDirectionBottom;
        _dragable = NO;
        _bounces = YES;
        _spring = YES;
        _behindViewScale = 0.9f;
        _behindViewAlpha = 1.0f;
        
        if (![self isIOS8]) {
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationChanged:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
        }
    }
    return self;
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

- (void)setDragable:(BOOL)dragable
{
    _dragable = dragable;
    if (self.isDragable) {
        self.gesture = [[ZFDetectScrollViewEndGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        self.gesture.delegate = self;
        [self.modalController.view addGestureRecognizer:self.gesture];
    }
}

- (void)setContentScrollView:(UIScrollView *)scrollView
{
    self.gesture.scrollview = scrollView;
}

- (void)animationEnded:(BOOL)transitionCompleted
{
    // Reset to our default state
    self.isInteractive = NO;
    self.transitionContext = nil;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.8;
}

#pragma mark - blur view methods

- (UIImage *)getScreenImage:(UIViewController *)viewController {
    // frame without status bar
    CGRect frame;
    if (UIDeviceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation)) {
        frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    } else {
        frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width);
    }
    // begin image context
    UIGraphicsBeginImageContext(frame.size);
    // get current context
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    
    // draw current view
    [viewController.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    // clip context to frame
    CGContextClipToRect(currentContext, frame);
    // get resulting cropped screenshot
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    // end image context
    UIGraphicsEndImageContext();
    return screenshot;
}

- (UIImage *)getBlurredImage:(UIImage *)imageToBlur {
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
        return [imageToBlur applyBlurWithRadius:0.5f tintColor:[UIColor clearColor] saturationDeltaFactor:1.0 maskImage:nil];
    }
    return imageToBlur;
}

- (UIImageView *)blurView:(UIViewController *)viewController {
    UIImageView *blurView = [UIImageView new];
    if (UIDeviceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation)) {
        blurView.frame = CGRectMake(0, 64, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    } else {
        blurView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width);
    }
    blurView.alpha = 1.0f;
    blurView.image = [self getBlurredImage:[self getScreenImage:viewController]];
    return blurView;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    if (self.isInteractive) {
        return;
    }
    // Grab the from and to view controllers from the context
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    
    if (!self.isDismiss) {
        
        CGRect startRect;
        
        [[transitionContext containerView] addSubview:toViewController.view];
        
        toViewController.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        
        if (self.direction == ZFModalTransitonDirectionBottom) {
            startRect = CGRectMake(0,
                                   [self screenHeightForCurrentOrientation],
                                   CGRectGetWidth(toViewController.view.bounds),
                                   CGRectGetHeight(toViewController.view.bounds));
        } else if (self.direction == ZFModalTransitonDirectionLeft) {
            startRect = CGRectMake(-CGRectGetWidth(toViewController.view.frame),
                                   [self screenHeightForCurrentOrientation] - CGRectGetHeight(toViewController.view.frame),
                                   CGRectGetWidth(toViewController.view.bounds),
                                   CGRectGetHeight(toViewController.view.bounds));
        } else if (self.direction == ZFModalTransitonDirectionRight) {
            startRect = CGRectMake(CGRectGetWidth(toViewController.view.frame),
                                   [self screenHeightForCurrentOrientation] - CGRectGetHeight(toViewController.view.frame),
                                   CGRectGetWidth(toViewController.view.bounds),
                                   CGRectGetHeight(toViewController.view.bounds));
        }
        
        CGPoint transformedPoint = CGPointApplyAffineTransform(startRect.origin, toViewController.view.transform);
        toViewController.view.frame = CGRectMake(transformedPoint.x, transformedPoint.y, startRect.size.width, startRect.size.height);
        
        [self addTapToDismissGestureRecognizer:fromViewController.view];
//        [fromViewController.view addSubview:[self blurView:fromViewController]];
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:self.spring ? 5 : 50
              initialSpringVelocity:15
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             
                             fromViewController.view.transform = CGAffineTransformScale(fromViewController.view.transform, self.behindViewScale, self.behindViewScale);
                             fromViewController.view.alpha = self.behindViewAlpha;
                             
                             toViewController.view.frame = CGRectMake(0,
                                                                      [self screenHeightForCurrentOrientation] - CGRectGetHeight(toViewController.view.frame),
                                                                      CGRectGetWidth(toViewController.view.frame),
                                                                      CGRectGetHeight(toViewController.view.frame));
                             
                             
                         } completion:^(BOOL finished) {
                             [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
                             
                         }];
    } else {
        
        [[transitionContext containerView] bringSubviewToFront:fromViewController.view];
        
        if (![self isIOS8]) {
            toViewController.view.layer.transform = CATransform3DScale(toViewController.view.layer.transform, self.behindViewScale, self.behindViewScale, 1);
        }
        
        toViewController.view.alpha = self.behindViewAlpha;
        [toViewController.view removeGestureRecognizer:self.backgroundTap];
        
        CGRect endRect;
        
        if (self.direction == ZFModalTransitonDirectionBottom) {
            endRect = CGRectMake(0,
                                 [self screenHeightForCurrentOrientation],
                                 CGRectGetWidth(fromViewController.view.frame),
                                 CGRectGetHeight(fromViewController.view.frame));
        } else if (self.direction == ZFModalTransitonDirectionLeft) {
            endRect = CGRectMake(-CGRectGetWidth(fromViewController.view.bounds),
                                 [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                                 CGRectGetWidth(fromViewController.view.frame),
                                 CGRectGetHeight(fromViewController.view.frame));
        } else if (self.direction == ZFModalTransitonDirectionRight) {
            endRect = CGRectMake(CGRectGetWidth(fromViewController.view.bounds),
                                 [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                                 CGRectGetWidth(fromViewController.view.frame),
                                 CGRectGetHeight(fromViewController.view.frame));
        }
        
        CGPoint transformedPoint = CGPointApplyAffineTransform(endRect.origin, fromViewController.view.transform);
        endRect = CGRectMake(transformedPoint.x, transformedPoint.y, endRect.size.width, endRect.size.height);
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:5
              initialSpringVelocity:15
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             CGFloat scaleBack = (1 / self.behindViewScale);
                             toViewController.view.layer.transform = CATransform3DScale(toViewController.view.layer.transform, scaleBack, scaleBack, 1);

                             toViewController.view.alpha = 1.0f;
                             fromViewController.view.frame = endRect;
                         } completion:^(BOOL finished) {
                             [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
                             
                         }];
    }
}

- (void)addTapToDismissGestureRecognizer:(UIView *)view {
    // add gesture recognition for tapping on a UIlabel within the header (UICollectionView supplementary view)
    self.backgroundTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissTap:)];
    // make your gesture recognizer priority
    self.backgroundTap.delaysTouchesBegan = YES;
    self.backgroundTap.numberOfTapsRequired = 1;
    
    [view addGestureRecognizer:self.backgroundTap];
}

- (void)handleDismissTap:(UITapGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateEnded) return;
    
    [self.modalController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Gesture

- (void)handlePan:(UIPanGestureRecognizer *)recognizer
{
    // Location reference
    CGPoint location = [recognizer locationInView:self.modalController.view.window];
    location = CGPointApplyAffineTransform(location, CGAffineTransformInvert(recognizer.view.transform));
    // Velocity reference
    CGPoint velocity = [recognizer velocityInView:[self.modalController.view window]];
    velocity = CGPointApplyAffineTransform(velocity, CGAffineTransformInvert(recognizer.view.transform));
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.isInteractive = YES;
        if (self.direction == ZFModalTransitonDirectionBottom) {
            self.panLocationStart = location.y;
        } else {
            self.panLocationStart = location.x;
        }
        [self.modalController dismissViewControllerAnimated:YES completion:nil];
    }
    
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGFloat animationRatio = 0;
        
        if (self.direction == ZFModalTransitonDirectionBottom) {
            animationRatio = (location.y - self.panLocationStart) / (CGRectGetHeight([self.modalController view].bounds));
        } else if (self.direction == ZFModalTransitonDirectionLeft) {
            animationRatio = (self.panLocationStart - location.x) / (CGRectGetWidth([self.modalController view].bounds));
        } else if (self.direction == ZFModalTransitonDirectionRight) {
            animationRatio = (location.x - self.panLocationStart) / (CGRectGetWidth([self.modalController view].bounds));
        }
        
        [self updateInteractiveTransition:animationRatio];
    } else if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        CGFloat velocityForSelectedDirection;
        
        if (self.direction == ZFModalTransitonDirectionBottom) {
            velocityForSelectedDirection = velocity.y;
        } else {
            velocityForSelectedDirection = velocity.x;
        }
        
        if (velocityForSelectedDirection > 100
            && (self.direction == ZFModalTransitonDirectionRight
                || self.direction == ZFModalTransitonDirectionBottom)) {
                [self finishInteractiveTransition];
            } else if (velocityForSelectedDirection < -100 && self.direction == ZFModalTransitonDirectionLeft) {
                [self finishInteractiveTransition];
            } else {
                [self cancelInteractiveTransition];
            }
        self.isInteractive = NO;
    }
}

#pragma mark -

-(void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    self.transitionContext = transitionContext;
    
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    if (![self isIOS8]) {
        toViewController.view.layer.transform = CATransform3DScale(toViewController.view.layer.transform, self.behindViewScale, self.behindViewScale, 1);
    }
    
    self.tempTransform = toViewController.view.layer.transform;
    
    toViewController.view.alpha = self.behindViewAlpha;
    [[transitionContext containerView] bringSubviewToFront:fromViewController.view];
    
}

- (void)updateInteractiveTransition:(CGFloat)percentComplete
{
    if (!self.bounces && percentComplete < 0) {
        percentComplete = 0;
    }
    
    id<UIViewControllerContextTransitioning> transitionContext = self.transitionContext;
    
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    CATransform3D transform = CATransform3DMakeScale(
                                                     1 + (((1 / self.behindViewScale) - 1) * percentComplete),
                                                     1 + (((1 / self.behindViewScale) - 1) * percentComplete), 1);
    toViewController.view.layer.transform = CATransform3DConcat(self.tempTransform, transform);
    
    toViewController.view.alpha = self.behindViewAlpha + ((1 - self.behindViewAlpha) * percentComplete);
    
    CGRect updateRect;
    if (self.direction == ZFModalTransitonDirectionBottom) {
        updateRect = CGRectMake(0,
                                ([self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame) + CGRectGetHeight(fromViewController.view.frame) * percentComplete),
                                CGRectGetWidth(fromViewController.view.frame),
                                CGRectGetHeight(fromViewController.view.frame));
    } else if (self.direction == ZFModalTransitonDirectionLeft) {
        updateRect = CGRectMake(-(CGRectGetWidth(fromViewController.view.bounds) * percentComplete),
                                [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                                CGRectGetWidth(fromViewController.view.frame),
                                CGRectGetHeight(fromViewController.view.frame));
    } else if (self.direction == ZFModalTransitonDirectionRight) {
        updateRect = CGRectMake(CGRectGetWidth(fromViewController.view.bounds) * percentComplete,
                                [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                                CGRectGetWidth(fromViewController.view.frame),
                                CGRectGetHeight(fromViewController.view.frame));
    }
    
    CGPoint transformedPoint = CGPointApplyAffineTransform(updateRect.origin, fromViewController.view.transform);
    updateRect = CGRectMake(transformedPoint.x, transformedPoint.y, updateRect.size.width, updateRect.size.height);
    
    fromViewController.view.frame = updateRect;
}

- (void)finishInteractiveTransition
{
    id<UIViewControllerContextTransitioning> transitionContext = self.transitionContext;
    
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    CGRect endRect;
    
    if (self.direction == ZFModalTransitonDirectionBottom) {
        endRect = CGRectMake(0,
                             [self screenHeightForCurrentOrientation],
                             CGRectGetWidth(fromViewController.view.frame),
                             CGRectGetHeight(fromViewController.view.frame));
    } else if (self.direction == ZFModalTransitonDirectionLeft) {
        endRect = CGRectMake(-CGRectGetWidth(fromViewController.view.bounds),
                             [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                             CGRectGetWidth(fromViewController.view.frame),
                             CGRectGetHeight(fromViewController.view.frame));
    } else if (self.direction == ZFModalTransitonDirectionRight) {
        endRect = CGRectMake(CGRectGetWidth(fromViewController.view.bounds),
                             [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                             CGRectGetWidth(fromViewController.view.frame),
                             CGRectGetHeight(fromViewController.view.frame));
    }
    
    [toViewController.view removeGestureRecognizer:self.backgroundTap];
    
    CGPoint transformedPoint = CGPointApplyAffineTransform(endRect.origin, fromViewController.view.transform);
    endRect = CGRectMake(transformedPoint.x, transformedPoint.y, endRect.size.width, endRect.size.height);
    
    [UIView animateWithDuration:[self transitionDuration:transitionContext]
                          delay:0
         usingSpringWithDamping:5
          initialSpringVelocity:5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         CGFloat scaleBack = (1 / self.behindViewScale);
                         toViewController.view.layer.transform = CATransform3DScale(self.tempTransform, scaleBack, scaleBack, 1);
                         toViewController.view.alpha = 1.0f;
                         fromViewController.view.frame = endRect;
                     } completion:^(BOOL finished) {
                         [transitionContext completeTransition:YES];
                         self.modalController = nil;
                     }];
    
}

- (void)cancelInteractiveTransition
{
    id<UIViewControllerContextTransitioning> transitionContext = self.transitionContext;
    
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    [UIView animateWithDuration:0.4
                          delay:0
         usingSpringWithDamping:5
          initialSpringVelocity:5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         
                         toViewController.view.layer.transform = self.tempTransform;
                         toViewController.view.alpha = self.behindViewAlpha;
                         
                         fromViewController.view.frame = CGRectMake(0,
                                                                    [self screenHeightForCurrentOrientation] - CGRectGetHeight(fromViewController.view.frame),
                                                                    CGRectGetWidth(fromViewController.view.frame),
                                                                    CGRectGetHeight(fromViewController.view.frame));
                         
                         
                     } completion:^(BOOL finished) {
                         [transitionContext completeTransition:NO];
                     }];
}

#pragma mark - UIViewControllerTransitioningDelegate Methods

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    self.isDismiss = NO;
    return self;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    self.isDismiss = YES;
    return self;
}

- (id <UIViewControllerInteractiveTransitioning>)interactionControllerForPresentation:(id <UIViewControllerAnimatedTransitioning>)animator
{
    return nil;
}

- (id <UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id <UIViewControllerAnimatedTransitioning>)animator
{
    // Return nil if we are not interactive
    if (self.isInteractive && self.dragable) {
        self.isDismiss = YES;
        return self;
    }
    
    return nil;
}

#pragma mark - Gesture Delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (self.direction == ZFModalTransitonDirectionBottom) {
        return YES;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (self.direction == ZFModalTransitonDirectionBottom) {
        return YES;
    }
    return NO;
}

#pragma mark - Utils

- (BOOL)isIOS8
{
    NSComparisonResult order = [[UIDevice currentDevice].systemVersion compare: @"8.0" options: NSNumericSearch];
    if (order == NSOrderedSame || order == NSOrderedDescending) {
        // OS version >= 8.0
        return YES;
    }
    return NO;
}

- (CGFloat)screenHeightForCurrentOrientation
{
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    if (orientation == UIDeviceOrientationFaceUp ||
        orientation == UIDeviceOrientationFaceDown ||
        orientation == UIDeviceOrientationPortraitUpsideDown ||
        orientation == UIDeviceOrientationPortrait ||
        orientation == UIDeviceOrientationUnknown) {
        return CGRectGetHeight([UIScreen mainScreen].bounds);
    }
    return CGRectGetWidth([UIScreen mainScreen].bounds);
}

#pragma mark - Orientation


- (void)orientationChanged:(NSNotification *)notification
{
//    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
//    if (orientation == UIDeviceOrientationPortraitUpsideDown || orientation == UIDeviceOrientationUnknown) {
//        return;
//    }
//    
//    UIViewController *toViewController = self.modalController.presentingViewController;
//    toViewController.view.transform = CGAffineTransformIdentity;
//    [self rotateLayer:toViewController.view.layer];
}

//-(void)rotateLayer: (CALayer *)layer
//{
//    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
//    
//    CGAffineTransform rotate;
//    CGAffineTransform scale = CGAffineTransformMakeScale(self.behindViewScale, self.behindViewScale);
//    
//    switch (orientation) {
//        case UIDeviceOrientationLandscapeLeft:
//            rotate = CGAffineTransformMakeRotation(M_PI_2);
//            break;
//        case UIDeviceOrientationLandscapeRight:
//            rotate = CGAffineTransformMakeRotation(-M_PI_2);
//            break;
//        default:
//            rotate = CGAffineTransformMakeRotation(0.0);
//            break;
//    }
//    
//    layer.affineTransform = CGAffineTransformConcat(rotate, scale);
//    
//    [layer setBounds:self.modalController.view.bounds];
//    [layer setPosition:CGPointMake(CGRectGetMidX(self.modalController.view.frame),
//                                   CGRectGetMidY(self.modalController.view.frame))];
//}

@end

// Gesture Class Implement
@interface ZFDetectScrollViewEndGestureRecognizer ()
@property (nonatomic, strong) NSNumber *isFail;
@end

@implementation ZFDetectScrollViewEndGestureRecognizer

- (void)reset
{
    [super reset];
    self.isFail = nil;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    
    if (!self.scrollview) {
        return;
    }
    
    if (self.state == UIGestureRecognizerStateFailed) return;
    CGPoint nowPoint = [touches.anyObject locationInView:self.view];
    CGPoint prevPoint = [touches.anyObject previousLocationInView:self.view];
    
    if (self.isFail) {
        if (self.isFail.boolValue) {
            self.state = UIGestureRecognizerStateFailed;
        }
        return;
    }
    
    if (nowPoint.y > prevPoint.y && self.scrollview.contentOffset.y <= 0) {
        self.isFail = @NO;
    } else if (self.scrollview.contentOffset.y >= 0) {
        self.state = UIGestureRecognizerStateFailed;
        self.isFail = @YES;
    } else {
        self.isFail = @NO;
    }
    
}

@end
