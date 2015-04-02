//
//  ZFModalTransitionAnimator.m
//
//  Created by Amornchai Kanokpullwad on 5/10/14.
//  Copyright (c) 2014 zoonref. All rights reserved.
//

#import "ZFModalTransitionAnimator.h"

@interface ZFModalTransitionAnimator ()
@property (nonatomic, strong) UIViewController *modalController;
@property (nonatomic, strong) ZFDetectScrollViewEndGestureRecognizer *gesture;
@property (nonatomic, strong) id<UIViewControllerContextTransitioning> transitionContext;
@property CGFloat panLocationStart;
@property BOOL isDismiss;
@property BOOL isInteractive;
@property CATransform3D tempTransform;
@property (nonatomic, strong) UIButton *dismissButton;
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
        
//        if (![self isIOS8]) {
//            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
//            [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(orientationChanged:)
//                                                     name:UIDeviceOrientationDidChangeNotification
//                                                   object:nil];
//        }
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
    return 0.6;
}

- (void)destroyDismissButton {
    if (self.dismissButton) {
        [self.dismissButton removeFromSuperview];
        self.dismissButton = nil;
    }
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
        
        [self addTopShadow:toViewController.view];
        
        CGRect overlayFrame = CGRectMake(0, 0, CGRectGetWidth(toViewController.view.frame), [self screenHeightForCurrentOrientation] - CGRectGetHeight(toViewController.view.frame));
        
        // If not transition to full screen view
        if (CGRectGetHeight(toViewController.view.frame) != [self screenHeightForCurrentOrientation]) {
            // Don't use UITapGestureRecognizer to avoid complex handling
            self.dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
            [self.dismissButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
            self.dismissButton.backgroundColor = [UIColor clearColor];
            self.dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.dismissButton.frame = overlayFrame;
            [fromViewController.view addSubview:self.dismissButton];
        }
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext]
                              delay:0
             usingSpringWithDamping:self.spring ? 0.8 : 1
              initialSpringVelocity:10
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
        [self destroyDismissButton];
        
        [[transitionContext containerView] bringSubviewToFront:fromViewController.view];
        
        if (![self isIOS8]) {
            toViewController.view.layer.transform = CATransform3DScale(toViewController.view.layer.transform, self.behindViewScale, self.behindViewScale, 1);
        }
        
        toViewController.view.alpha = self.behindViewAlpha;
        
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
        
        if (self.behindViewScale < 1.0) {
            [UIView animateWithDuration:[self transitionDuration:transitionContext]
                                  delay:0
                 usingSpringWithDamping:10
                  initialSpringVelocity:10
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 CGFloat scaleBack = (1 / self.behindViewScale);
                                 toViewController.view.layer.transform = CATransform3DScale(toViewController.view.layer.transform, scaleBack, scaleBack, 1);
                             } completion:nil];
        }
        
        [UIView animateWithDuration:[self transitionDuration:transitionContext] / 2
                              delay:0
             usingSpringWithDamping:1
              initialSpringVelocity:20
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
                             fromViewController.view.frame = endRect;
                             toViewController.view.alpha = 1.0f;
                         } completion:^(BOOL finished) {
                             [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
                         }];
    }
}

- (void)addTopShadow:(UIView *)view {
    CALayer *borderLayer = [CALayer layer];
    borderLayer.borderColor = [UIColor colorWithWhite:0.800 alpha:1.000].CGColor;
    borderLayer.borderWidth = 0.5;
    borderLayer.frame = CGRectMake(0, 0, view.frame.size.width, 1);
    [view.layer addSublayer:borderLayer];
    
//    view.layer.shadowColor = [[UIColor blackColor] CGColor];
//    view.layer.shadowOffset = CGSizeMake(0, -1);
//    view.layer.shadowRadius = 5.0;
//    view.layer.shadowOpacity = 0.3;
//    view.layer.shouldRasterize = YES;
//    view.layer.rasterizationScale = [[UIScreen mainScreen] scale];
}

- (void)dismiss {
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
    
    // reset to zero if x and y has unexpected value to prevent crash
    if (isnan(updateRect.origin.x) || isinf(updateRect.origin.x)) {
        updateRect.origin.x = 0;
    }
    if (isnan(updateRect.origin.y) || isinf(updateRect.origin.y)) {
        updateRect.origin.y = 0;
    }
    
    CGPoint transformedPoint = CGPointApplyAffineTransform(updateRect.origin, fromViewController.view.transform);
    updateRect = CGRectMake(transformedPoint.x, transformedPoint.y, updateRect.size.width, updateRect.size.height);
    
    fromViewController.view.frame = updateRect;
}

- (void)finishInteractiveTransition
{
    [self destroyDismissButton];
    
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
    BOOL result = NO;
    
    if (self.direction == ZFModalTransitonDirectionBottom) {
        result = YES;
    }
    
    return result;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    BOOL result = NO;
    
    if (self.direction == ZFModalTransitonDirectionBottom) {
        result = YES;
    }

    return result;
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
    
    if (nowPoint.y > prevPoint.y && self.scrollview.contentOffset.y < 0) {
        self.isFail = @NO;
    } else if (self.scrollview.contentOffset.y >= -self.scrollview.contentInset.top) { // PAUL:
        self.state = UIGestureRecognizerStateFailed;
        self.isFail = @YES;
    } else {
        self.isFail = @NO;
    }
}

@end
