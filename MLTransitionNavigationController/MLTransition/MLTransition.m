//
//  MLTransition.m
//  MLTransitionNavigationController
//
//  Created by molon on 7/7/14.
//  Copyright (c) 2014 molon. All rights reserved.
//

#import "MLTransition.h"
#import <objc/runtime.h>
#import "MLTransitionAnimation.h"

//设置一个默认的全局使用的type，默认是普通拖返模式
static MLTransitionGestureRecognizerType __MLTransitionGestureRecognizerType = MLTransitionGestureRecognizerTypePan;
//标识是否生效了
static BOOL __MLTransition_BeInvoke = NO;

#pragma mark - hook大法
//静态就交换静态，实例方法就交换实例方法
void __MLTransition_Swizzle(Class c, SEL origSEL, SEL newSEL)
{
    //获取实例方法
    Method origMethod = class_getInstanceMethod(c, origSEL);
    Method newMethod = nil;
	if (!origMethod) {
        //获取静态方法
		origMethod = class_getClassMethod(c, origSEL);
        newMethod = class_getClassMethod(c, newSEL);
    }else{
        newMethod = class_getInstanceMethod(c, newSEL);
    }
    
    if (!origMethod||!newMethod) {
        return;
    }
    
    //自身已经有了就添加不成功，直接交换即可
    if(class_addMethod(c, origSEL, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))){
        //添加成功一般情况是因为，origSEL本身是在c的父类里。这里添加成功了一个继承方法。
        class_replaceMethod(c, newSEL, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    }else{
        method_exchangeImplementations(origMethod, newMethod);
	}
}

#pragma mark - UIGestureRecognizer category interface
@interface UIGestureRecognizer(__MLTransistion)

@property (nonatomic, assign) UINavigationController *__MLTransition_NavController;

@end

#pragma mark - UINavigationController category interface
@interface UINavigationController(__MLTrasition)

/**
 *  每个导航器都添加一个拖动手势
 */
@property (nonatomic, strong) UIPanGestureRecognizer *__MLTransition_panGestureRecognizer;

- (void)__MLTransition_Hook_ViewDidLoad;
- (void)__MLTransition_Hook_Dealloc;

@end

#pragma mark - NSObject category interface
@interface NSObject(__MLTransistion)

@end

#pragma mark - MLTransition
/**
 *  这个单例对象作为开启点，并且作为手势的delegate和target
 */
@interface MLTransition()<UIGestureRecognizerDelegate,UINavigationControllerDelegate>

/**
 *  拖返交互时的动画控制器
 */
@property (nonatomic, strong) UIPercentDrivenInteractiveTransition *popInteractiveTransition;

/**
 *  动画类
 */
@property (nonatomic, strong) MLTransitionAnimation *animation;

/**
 *  是否在交互中
 */
@property (nonatomic, assign) BOOL isInteractiving;

@end

@implementation MLTransition

+ (instancetype)shareInstance {
    static MLTransition *_shareInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shareInstance = [[[self class] alloc]init];
    });
    return _shareInstance;
}

+ (void)validatePanPackWithMLTransitionGestureRecognizerType:(MLTransitionGestureRecognizerType)type
{
    //IOS7以下不可用
    if ([[[UIDevice currentDevice] systemVersion]floatValue]<7.0) {
        return;
    }
    
    //启用hook，自动对每个导航器开启拖返功能，整个程序的生命周期只允许执行一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        //设置记录type,并且执行hook
        __MLTransitionGestureRecognizerType = type;
        
        __MLTransition_Swizzle([UINavigationController class],@selector(viewDidLoad),@selector(__MLTransition_Hook_ViewDidLoad));
        __MLTransition_Swizzle([UINavigationController class], NSSelectorFromString(@"dealloc"),@selector(__MLTransition_Hook_Dealloc));
        
        __MLTransition_BeInvoke = YES;
    });
    
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.popInteractiveTransition = [UIPercentDrivenInteractiveTransition new];
        self.popInteractiveTransition.completionCurve = UIViewAnimationCurveLinear;
        self.animation = [MLTransitionAnimation new];
    }
    return self;
}

#pragma mark GestureRecognizer delegate
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)recognizer
{
    UINavigationController *navVC = recognizer.__MLTransition_NavController;
    
    if ([navVC.transitionCoordinator isAnimated]||
        navVC.viewControllers.count < 2) {
        return NO;
    }
    
    //普通拖曳模式，如果开始方向不对即不启用
    if (__MLTransitionGestureRecognizerType==MLTransitionGestureRecognizerTypePan){
        CGPoint velocity = [recognizer velocityInView:navVC.view];
        if(velocity.x<=0) {
            //NSLog(@"不是右滑的");
            return NO;
        }
        
        CGPoint translation = [recognizer translationInView:navVC.view];
        translation.x = translation.x==0?0.00001f:translation.x;
        CGFloat ratio = (fabs(translation.y)/fabs(translation.x));
        //因为上滑的操作相对会比较频繁，所以角度限制少点
        if ((translation.y>0&&ratio>0.618f)||(translation.y<0&&ratio>0.2f)) {
            //NSLog(@"右滑角度不在范围内");
            return NO;
        }
    }
    
    return YES;
}


#pragma mark GestureRecognizer handle
- (void)handlePopRecognizer:(UIPanGestureRecognizer*)recognizer {
    UINavigationController *navVC = recognizer.__MLTransition_NavController;
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _isInteractiving = YES;
        
        //开始pop
        [navVC popViewControllerAnimated:YES];
        return;
    }
    
    if (!_isInteractiving) {
        return;
    }
    
    CGFloat progress = [recognizer translationInView:navVC.view].x / (navVC.view.bounds.size.width * 1.0f)-0.05f; //少点不会显得飘
    progress = MIN(1.0, MAX(0.0, progress));
    
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        //因为上下距离太多，所以取消
        if (fabs([recognizer translationInView:navVC.view].y)>120.0f) {
            //            NSLog(@"因为上下距离太多，所以取消");
            [_popInteractiveTransition cancelInteractiveTransition];
            _isInteractiving = NO;
        }else{
            //中途上下速率太快就认为想取消
            CGPoint velocity = [recognizer velocityInView:navVC.view];
            if (fabs(velocity.y)>500.0f) {
                //检测和x速率的比例是不是inf，是的话，说明明显有向下移动的痕迹
                velocity.x = velocity.x==0?0.000001f:velocity.x;
                if (isinf(fabs(velocity.y)/fabs(velocity.x))) {
                    //                    NSLog(@"因为上下速率太快，所以取消");
                    [_popInteractiveTransition cancelInteractiveTransition];
                    _isInteractiving = NO;
                }
            }
        }
        
        if (_isInteractiving) {
            //根据拖动调整transition状态
            [_popInteractiveTransition updateInteractiveTransition:progress];
        }
    }else if ((recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled)) {
        //结束或者取消了手势，根据方向和速率来判断应该完成transition还是取消transition
        CGFloat velocityX = [recognizer velocityInView:navVC.view].x; //我们只关心x的速率
        
#define kTooFastVelocity 350.0f
        if (velocityX > kTooFastVelocity) { //向右速率太快就完成
            [_popInteractiveTransition finishInteractiveTransition];
        }else if (velocityX < -kTooFastVelocity){ //向左速率太快就取消
            [_popInteractiveTransition cancelInteractiveTransition];
        }else{
            if (progress > 0.7f || (progress>=0.10f&&velocityX>0.0f)) {
                [_popInteractiveTransition finishInteractiveTransition];
            }else{
                [_popInteractiveTransition cancelInteractiveTransition];
            }
        }
        _isInteractiving = NO;
    }
    
}

@end

#pragma mark - NSObject category implementation

/**
 *  这样的话，即使不是UINavigationController的delegate不是我们的单例，也可以捕获到。
 *  除非有object重载了这俩方法
 */
@implementation NSObject(__MLTransistion)


#pragma mark UINavigationControllerDelegate
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation
                                               fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC {
    
    if (!__MLTransition_BeInvoke) {
        return nil;
    }
    
    if (operation == UINavigationControllerOperationPop) {
        MLTransitionAnimation *animation = [MLTransition shareInstance].animation;
        animation.type = MLTransitionAnimationTypePop;
        return animation;
    }else if (operation == UINavigationControllerOperationPush){
        MLTransitionAnimation *animation = [MLTransition shareInstance].animation;
        animation.type = MLTransitionAnimationTypePush;
        return animation;
    }
    
    return nil;
}

- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController
                         interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animationController {
    if (!__MLTransition_BeInvoke) {
        return nil;
    }
    
    MLTransitionAnimation *animation = [MLTransition shareInstance].animation;
    if ([animation isEqual:animationController]&&animation.type==MLTransitionAnimationTypePop) {
        return [MLTransition shareInstance].isInteractiving?[MLTransition shareInstance].popInteractiveTransition:nil;
    }
    
    return nil;
}


@end

#pragma mark - UIGestureRecognizer category implementation
NSString * const kMLTransition_NavController_OfPan = @"__MLTransition_NavController_OfPan";

@implementation UIGestureRecognizer(__MLTransistion)

- (void)set__MLTransition_NavController:(UINavigationController *)__MLTransition_NavController
{
    [self willChangeValueForKey:kMLTransition_NavController_OfPan];
	objc_setAssociatedObject(self, &kMLTransition_NavController_OfPan, __MLTransition_NavController, OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:kMLTransition_NavController_OfPan];
}

- (UIViewController *)__MLTransition_NavController
{
	return objc_getAssociatedObject(self, &kMLTransition_NavController_OfPan);
}

@end

#pragma mark - UINavigationController category implementation
NSString * const k__MLTransition_GestureRecognizer = @"__MLTransition_GestureRecognizer";

@implementation UINavigationController(__MLTrasition)

#pragma mark getter and setter
- (void)set__MLTransition_panGestureRecognizer:(UIPanGestureRecognizer *)__MLTransition_panGestureRecognizer
{
    [self willChangeValueForKey:k__MLTransition_GestureRecognizer];
	objc_setAssociatedObject(self, &k__MLTransition_GestureRecognizer, __MLTransition_panGestureRecognizer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:k__MLTransition_GestureRecognizer];
}

- (UIPanGestureRecognizer *)__MLTransition_panGestureRecognizer
{
	return objc_getAssociatedObject(self, &k__MLTransition_GestureRecognizer);
}

#pragma mark hook
- (void)__MLTransition_Hook_ViewDidLoad
{
    [self __MLTransition_Hook_ViewDidLoad];
    
    //初始化拖返手势
    if (!self.__MLTransition_panGestureRecognizer) {
        UIPanGestureRecognizer *gestureRecognizer = nil;
        if (__MLTransitionGestureRecognizerType == MLTransitionGestureRecognizerTypeScreenEdgePan) {
            gestureRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:[MLTransition shareInstance] action:@selector(handlePopRecognizer:)];
            ((UIScreenEdgePanGestureRecognizer*)gestureRecognizer).edges = UIRectEdgeLeft;
        }else{
            gestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:[MLTransition shareInstance] action:@selector(handlePopRecognizer:)];
        }
        
        gestureRecognizer.__MLTransition_NavController = self;
        gestureRecognizer.delegate = [MLTransition shareInstance];
        
        self.__MLTransition_panGestureRecognizer = gestureRecognizer;
        [self.view addGestureRecognizer:gestureRecognizer];
        
        //放在这里是为了保证只会执行一次
        //自动对delegate进行监视，如果发现其被置为nil，则用我们的单例作为delegate
        //PS要记住，其delegate是assgin属性的，不用时候记得重置为nil
        [self addObserver:self forKeyPath:@"delegate" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial context:nil];
    }
}


- (void)__MLTransition_Hook_Dealloc
{
    //清理下该清理的
    [self removeObserver:self forKeyPath:@"delegate" context:nil];
    
    //是我们的单例，我们才能放心愉快的重置掉。
    if ([self.delegate isEqual:[MLTransition shareInstance]]) {
        self.delegate = nil;
    }
    
    self.__MLTransition_panGestureRecognizer.delegate = nil;
    self.__MLTransition_panGestureRecognizer.__MLTransition_NavController = nil;
    
    [self __MLTransition_Hook_Dealloc];
}


#pragma mark KVO
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([@"delegate" isEqualToString:keyPath]) {
        id new = [change objectForKey:NSKeyValueChangeNewKey];
        //        NSLog(@"%@",new);
        if ([new isKindOfClass:[NSNull class]]) {
            self.delegate = [MLTransition shareInstance];
        }
    }else{
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end


#pragma mark - UIScrollView category ，可让scrollView在一个良好的关系下并存
@interface UIScrollView(__MLTransistion)

@end

@implementation UIScrollView(__MLTransistion)

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([gestureRecognizer isEqual:self.panGestureRecognizer]) {
        if (self.contentSize.width>self.frame.size.width) { //如果此scrollView有横向滚动的可能当然就需要忽略了。
            return NO;
        }
        if (otherGestureRecognizer.__MLTransition_NavController) {
            //说明这玩意是我们的手势
            return YES;
        }
    }
    return NO;
}

@end

