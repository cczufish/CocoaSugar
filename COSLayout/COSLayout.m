// COSLayout.m
//
// Copyright (c) 2014 Tianyong Tang
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE
// AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

#import "COSLayout.h"
#import "COSLayoutParser.h"

#import <objc/runtime.h>

#define COS_STREQ(a, b) (strcmp(a, b) == 0)

#define COS_SUPERVIEW_PLACEHOLDER [NSNull null]

@class COSLayoutRule;

typedef float(^COSFloatBlock)(UIView *);
typedef float(^COSCoordBlock)(COSLayoutRule *);

typedef NS_ENUM(NSInteger, COSLayoutDir) {
    COSLayoutDirv,
    COSLayoutDirh
};

static const void *COSLayoutKey = &COSLayoutKey;
static const void *COSLayoutDriverKey = &COSLayoutDriverKey;

static NSMutableSet *swizzledDriverClasses = nil;
static NSMutableSet *swizzledLayoutClasses = nil;

static NSString *COSLayoutCycleExceptionName = @"COSLayoutCycleException";
static NSString *COSLayoutCycleExceptionDesc = @"Layout can not be solved because of cycle";

static NSString *COSLayoutSyntaxExceptionName = @"COSLayoutSyntaxException";
static NSString *COSLayoutSyntaxExceptionDesc = @"Layout rule has a syntax error";


@interface COSCoord : NSObject

+ (instancetype)coordWithFloat:(float)value;
+ (instancetype)coordWithPercentage:(float)percentage;
+ (instancetype)coordWithBlock:(COSCoordBlock)block;

@property (nonatomic, strong) NSMutableSet *dependencies;
@property (nonatomic, copy) COSCoordBlock block;

- (instancetype)add:(COSCoord *)other;
- (instancetype)sub:(COSCoord *)other;
- (instancetype)mul:(COSCoord *)other;
- (instancetype)div:(COSCoord *)other;

@end


@interface COSCoords : NSObject

+ (instancetype)coordsOfView:(UIView *)view;

@end


@interface COSLayoutRule : NSObject

+ (COSLayoutRule *)layoutRuleWithView:(UIView *)view
    name:(NSString *)name
    coord:(COSCoord *)coord
    dir:(COSLayoutDir)dir;

@property (nonatomic, weak) UIView *view;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) COSCoord *coord;
@property (nonatomic, assign) COSLayoutDir dir;

@end


@interface COSLayoutRuleHub : NSObject

@property (nonatomic, readonly) NSMutableArray *vRules;
@property (nonatomic, readonly) NSMutableArray *hRules;

- (void)vAddRule:(COSLayoutRule *)rule;
- (void)hAddRule:(COSLayoutRule *)rule;

@end


@interface COSLayout ()

@property (nonatomic, weak) UIView *view;

@property (nonatomic, strong) COSLayoutRuleHub *ruleHub;
@property (nonatomic, strong) NSMutableDictionary *ruleMap;

@property (nonatomic, strong) COSCoord *minw;
@property (nonatomic, strong) COSCoord *maxw;

@property (nonatomic, strong) COSCoord *minh;
@property (nonatomic, strong) COSCoord *maxh;

@property (nonatomic, strong) COSCoord *tt;
@property (nonatomic, strong) COSCoord *tb;

@property (nonatomic, strong) COSCoord *ll;
@property (nonatomic, strong) COSCoord *lr;

@property (nonatomic, strong) COSCoord *bb;
@property (nonatomic, strong) COSCoord *bt;

@property (nonatomic, strong) COSCoord *rr;
@property (nonatomic, strong) COSCoord *rl;

@property (nonatomic, strong) COSCoord *ct;
@property (nonatomic, strong) COSCoord *cl;
@property (nonatomic, strong) COSCoord *cb;
@property (nonatomic, strong) COSCoord *cr;

@property (nonatomic, assign) CGRect frame;

- (instancetype)initWithView:(UIView *)view;

- (void)updateLayoutDriver;

- (NSSet *)dependencies;

- (void)startLayout;

@end


@interface COSLayoutRulesSolver : NSObject

@property (nonatomic, weak) UIView *view;

- (CGRect)solveTt:(NSArray *)rules;
- (CGRect)solveTtCt:(NSArray *)rules;
- (CGRect)solveTtBt:(NSArray *)rules;

- (CGRect)solveLl:(NSArray *)rules;
- (CGRect)solveLlCl:(NSArray *)rules;
- (CGRect)solveLlRl:(NSArray *)rules;

- (CGRect)solveBt:(NSArray *)rules;
- (CGRect)solveBtCt:(NSArray *)rules;
- (CGRect)solveBtTt:(NSArray *)rules;

- (CGRect)solveRl:(NSArray *)rules;
- (CGRect)solveRlCl:(NSArray *)rules;
- (CGRect)solveRlLl:(NSArray *)rules;

- (CGRect)solveCt:(NSArray *)rules;
- (CGRect)solveCtTt:(NSArray *)rules;
- (CGRect)solveCtBt:(NSArray *)rules;

- (CGRect)solveCl:(NSArray *)rules;
- (CGRect)solveClLl:(NSArray *)rules;
- (CGRect)solveClRl:(NSArray *)rules;

@end


@interface COSLayoutSolver : NSObject

+ (instancetype)layoutSolverOfView:(UIView *)view;

@property (nonatomic, weak) UIView *view;

- (instancetype)initWithView:(UIView *)view;

- (void)solve;

@end


@interface COSLayoutDriver : NSObject

@property (nonatomic, weak) UIView *view;

@property (nonatomic, strong) COSLayoutSolver *solver;

- (instancetype)initWithView:(UIView *)view;

- (void)beginSolves;
- (void)endSolves;

@end


@implementation COSLayoutRule

+ (COSLayoutRule *)layoutRuleWithView:(UIView *)view
    name:(NSString *)name
    coord:(COSCoord *)coord
    dir:(COSLayoutDir)dir
{
    COSLayoutRule *rule = [[COSLayoutRule alloc] init];

    rule.view = view;
    rule.name = name;
    rule.coord = coord;
    rule.dir = dir;

    return rule;
}

@end


@implementation COSLayoutRuleHub

@synthesize vRules = _vRules;
@synthesize hRules = _hRules;

- (NSMutableArray *)vRules {
    return _vRules ?: (_vRules = [[NSMutableArray alloc] init]);
}

- (NSMutableArray *)hRules {
    return _hRules ?: (_hRules = [[NSMutableArray alloc] init]);
}

- (void)addRule:(COSLayoutRule *)rule toRules:(NSMutableArray *)rules {
    [rules filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.name != %@", rule.name]];

    if ([rules count] > 1) [rules removeObjectAtIndex:0];

    if (rule.coord) [rules addObject:rule];
}

- (void)vAddRule:(COSLayoutRule *)rule {
    [self addRule:rule toRules:self.vRules];
}

- (void)hAddRule:(COSLayoutRule *)rule {
    [self addRule:rule toRules:self.hRules];
}

@end


#define COS_FRAME_WIDTH  (frame.size.width)
#define COS_FRAME_HEIGHT (frame.size.height)

#define COS_SUPERVIEW_WIDTH  (view.superview.bounds.size.width)
#define COS_SUPERVIEW_HEIGHT (view.superview.bounds.size.height)

#define COSLAYOUT_FRAME(view) \
    ([objc_getAssociatedObject(view, COSLayoutKey) frame])

#define COSLAYOUT_SOLVE_SINGLE_H(var, left)  \
do {                                         \
    COSLayoutRule *rule = rules[0];          \
    float var = [[rule coord] block](rule);  \
    UIView *view = _view;                    \
    CGRect frame = COSLAYOUT_FRAME(view);    \
    frame.origin.x = (left);                 \
    return frame;                            \
} while (0)

#define COSLAYOUT_SOLVE_SINGLE_V(var, top)   \
do {                                         \
    COSLayoutRule *rule = rules[0];          \
    float var = [[rule coord] block](rule);  \
    UIView *view = _view;                    \
    CGRect frame = COSLAYOUT_FRAME(view);    \
    frame.origin.y = (top);                  \
    return frame;                            \
} while (0)

#define COSLAYOUT_SOLVE_DOUBLE_H(var1, var2, width_, left)  \
do {                                                        \
    COSLayoutRule *rule0 = rules[0];                        \
    COSLayoutRule *rule1 = rules[1];                        \
    float var1 = [[rule0 coord] block](rule0);              \
    float var2 = [[rule1 coord] block](rule1);              \
    UIView *view = _view;                                   \
    CGRect frame = COSLAYOUT_FRAME(view);                   \
    frame.size.width = [self calcWidth:(width_)];           \
    frame.origin.x = (left);                                \
    return frame;                                           \
} while (0)

#define COSLAYOUT_SOLVE_DOUBLE_V(var1, var2, height_, top)  \
do {                                                        \
    COSLayoutRule *rule0 = rules[0];                        \
    COSLayoutRule *rule1 = rules[1];                        \
    float var1 = [[rule0 coord] block](rule0);              \
    float var2 = [[rule1 coord] block](rule1);              \
    UIView *view = _view;                                   \
    CGRect frame = COSLAYOUT_FRAME(view);                   \
    frame.size.height = [self calcHeight:(height_)];        \
    frame.origin.y = (top);                                 \
    return frame;                                           \
} while (0)

#define COS_MM_RAW_VALUE(layout, var)               \
({                                                  \
    COSLayoutRule *rule = layout.ruleMap[@(#var)];  \
                                                    \
    rule.coord ?                                    \
    rule.coord.block(rule) :                        \
    NAN;                                            \
})

#define COS_VALID_DIM(value) (!isnan(value) && (value) >= 0)


@implementation COSLayoutRulesSolver

- (CGFloat)calcWidth:(CGFloat)width {
    COSLayout *layout = objc_getAssociatedObject(_view, COSLayoutKey);

    CGFloat minw = COS_MM_RAW_VALUE(layout, minw);

    if (COS_VALID_DIM(minw) && width < minw) {
        width = minw;
    }

    CGFloat maxw = COS_MM_RAW_VALUE(layout, maxw);

    if (COS_VALID_DIM(maxw) && width > maxw) {
        width = maxw;
    }

    return MAX(width, 0);
}

- (CGFloat)calcHeight:(CGFloat)height {
    COSLayout *layout = objc_getAssociatedObject(_view, COSLayoutKey);

    CGFloat minh = COS_MM_RAW_VALUE(layout, minh);

    if (COS_VALID_DIM(minh) && height < minh) {
        height = minh;
    }

    CGFloat maxh = COS_MM_RAW_VALUE(layout, maxh);

    if (COS_VALID_DIM(maxh) && height > maxh) {
        height = maxh;
    }

    return MAX(height, 0);
}

- (CGRect)solveTt:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_V(top, top);
}

- (CGRect)solveTtCt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(top, axisY, (axisY - top) * 2, top);
}

- (CGRect)solveTtBt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(top, bottom, bottom - top, top);
}

- (CGRect)solveLl:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_H(left, left);
}

- (CGRect)solveLlCl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(left, axisX, (axisX - left) * 2, left);
}

- (CGRect)solveLlRl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(left, right, right - left, left);
}

- (CGRect)solveBt:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_V(bottom, bottom - COS_FRAME_HEIGHT);
}

- (CGRect)solveBtCt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(bottom, axisY, (bottom - axisY) * 2, axisY - COS_FRAME_HEIGHT / 2);
}

- (CGRect)solveBtTt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(bottom, top, bottom - top, top);
}

- (CGRect)solveRl:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_H(right, right - COS_FRAME_WIDTH);
}

- (CGRect)solveRlCl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(right, axisX, (right - axisX) * 2, axisX - COS_FRAME_WIDTH / 2);
}

- (CGRect)solveRlLl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(right, left, right - left, left);
}

- (CGRect)solveCt:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_V(axisY, axisY - COS_FRAME_HEIGHT / 2);
}

- (CGRect)solveCtTt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(axisY, top, (axisY - top) * 2, top);
}

- (CGRect)solveCtBt:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_V(axisY, bottom, (bottom - axisY) * 2, bottom - COS_FRAME_HEIGHT);
}

- (CGRect)solveCl:(NSArray *)rules {
    COSLAYOUT_SOLVE_SINGLE_H(axisX, axisX - COS_FRAME_WIDTH / 2);
}

- (CGRect)solveClLl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(axisX, left, (axisX - left) * 2, left);
}

- (CGRect)solveClRl:(NSArray *)rules {
    COSLAYOUT_SOLVE_DOUBLE_H(axisX, right, (right - axisX) * 2, right - COS_FRAME_WIDTH);
}

@end


enum COSLayoutVisitStat {
    COSLayoutVisitStatUnvisited,
    COSLayoutVisitStatVisiting,
    COSLayoutVisitStatVisited
};

typedef enum COSLayoutVisitStat COSLayoutVisitStat;

static const void *COSVisitKey = &COSVisitKey;

NS_INLINE
void COSMakeViewUnvisited(UIView *view) {
    objc_setAssociatedObject(view, COSVisitKey, nil, OBJC_ASSOCIATION_RETAIN);
}

NS_INLINE
void COSMakeViewVisiting(UIView *view) {
    objc_setAssociatedObject(view, COSVisitKey, @(COSLayoutVisitStatVisiting), OBJC_ASSOCIATION_RETAIN);
}

NS_INLINE
void COSMakeViewVisited(UIView *view) {
    objc_setAssociatedObject(view, COSVisitKey, @(COSLayoutVisitStatVisited), OBJC_ASSOCIATION_RETAIN);
}


@interface COSLayoutIterator : NSObject

@property (nonatomic, strong) NSSet *layouts;

- (NSMutableArray *)viewTopo;

- (void)iterate;

@end


@implementation COSLayoutIterator {
    NSMutableSet *_viewSet;
    NSMutableArray *_viewTopo;
}

- (NSMutableSet *)viewSet {
    return (_viewSet ?: (_viewSet = [[NSMutableSet alloc] init]));
}

- (NSMutableArray *)viewTopo {
    return (_viewTopo ?: (_viewTopo = [[NSMutableArray alloc] init]));
}

- (void)iterate {
    [self makeViewSet];
    [self cleanVisitFlag];
    [self makeViewTopo];
    [self cleanVisitFlag];
}

- (void)makeViewSet {
    for (COSLayout *layout in _layouts) {
        [self makeViewSetVisit:layout.view];
    }
}

- (void)makeViewSetVisit:(UIView *)view {
    COSMakeViewVisiting(view);

    COSLayout *layout = objc_getAssociatedObject(view, COSLayoutKey);

    for (UIView *adjView in [layout dependencies]) {
        NSNumber *stat = objc_getAssociatedObject(adjView, COSVisitKey);
        COSLayoutVisitStat istat = stat ? [stat intValue] : COSLayoutVisitStatUnvisited;

        if (istat == COSLayoutVisitStatUnvisited) {
            [self makeViewSetVisit:adjView];
        } else if (istat == COSLayoutVisitStatVisiting) {
            [self cleanVisitFlag];
            [self cycleError];
        }
    }

    [[self viewSet] addObject:view];

    COSMakeViewVisited(view);
}

- (void)makeViewTopo {
    for (UIView *view in [self viewSet]) {
        NSNumber *stat = objc_getAssociatedObject(view, COSVisitKey);
        COSLayoutVisitStat istat = stat ? [stat intValue] : COSLayoutVisitStatUnvisited;
        if (istat == COSLayoutVisitStatUnvisited) {
            [self makeViewTopoVisit:view];
        }
    }
}

- (void)makeViewTopoVisit:(UIView *)view {
    COSMakeViewVisiting(view);

    COSLayout *layout = objc_getAssociatedObject(view, COSLayoutKey);

    for (UIView *adjView in [layout dependencies]) {
        NSNumber *stat = objc_getAssociatedObject(adjView, COSVisitKey);
        COSLayoutVisitStat istat = stat ? [stat intValue] : COSLayoutVisitStatUnvisited;

        if (istat == COSLayoutVisitStatUnvisited) {
            [self makeViewTopoVisit:adjView];
        } else if (istat == COSLayoutVisitStatVisiting) {
            [self cleanVisitFlag];
            [self cycleError];
        }
    }

    [[self viewTopo] addObject:view];

    COSMakeViewVisited(view);
}

- (void)cleanVisitFlag {
    for (UIView *view in [self viewSet]) {
        COSMakeViewUnvisited(view);
    }

    for (UIView *view in [self viewTopo]) {
        COSMakeViewUnvisited(view);
    }
}

- (void)cycleError {
    [NSException raise:COSLayoutCycleExceptionName format:@"%@", COSLayoutCycleExceptionDesc];
}

@end


@implementation COSLayoutSolver

+ (instancetype)layoutSolverOfView:(UIView *)view {
    static const void *layoutSolverKey = &layoutSolverKey;

    COSLayoutSolver *solver = objc_getAssociatedObject(view, layoutSolverKey);

    if (!solver) {
        solver = [[COSLayoutSolver alloc] initWithView:view];

        objc_setAssociatedObject(view, layoutSolverKey, solver, OBJC_ASSOCIATION_RETAIN);
    }

    return solver;
}

- (instancetype)initWithView:(UIView *)view {
    self = [super init];

    if (self) {
        _view = view;
    }

    return self;
}

- (void)solve {
    NSArray *subviews = [self.view subviews];

    NSMutableSet *layouts = [[NSMutableSet alloc] init];

    for (UIView *subview in subviews) {
        COSLayout *layout = objc_getAssociatedObject(subview, COSLayoutKey);

        if (layout) {
            [layouts addObject:layout];
        }
    }

    COSLayoutIterator *iterator = [[COSLayoutIterator alloc] init];

    iterator.layouts = layouts;

    [iterator iterate];

    for (UIView *view in [iterator viewTopo]) {
        if (view == _view) continue;

        COSLayout *layout = objc_getAssociatedObject(view, COSLayoutKey);

        [layout startLayout];
    }
}

@end


@implementation COSLayoutDriver

{
    NSInteger stackId;
}

- (instancetype)initWithView:(UIView *)view {
    self = [super init];

    if (self) {
        _view = view;
    }

    return self;
}

- (COSLayoutSolver *)solver {
    return _solver ?: (_solver = [COSLayoutSolver layoutSolverOfView:self.view]);
}

- (void)beginSolves {
    stackId += 1;
}

- (void)endSolves {
    if ((--stackId) == 0) {
        [self.solver solve];
    }
}

@end


#define COSCOORD_MAKE(dependencies_, expr)       \
({                                               \
    __weak UIView *__view = _view;               \
                                                 \
    COSCoord *coord = [[COSCoord alloc] init];   \
                                                 \
    coord.dependencies = (dependencies_);        \
    coord.block = ^float(COSLayoutRule *rule) {  \
        UIView *view = __view;                   \
                                                 \
        return (expr);                           \
    };                                           \
                                                 \
    coord;                                       \
})

#define COSLAYOUT_ADD_RULE(var, dir_)        \
do {                                         \
    _##var = (var);                          \
    NSString *name = @(#var);                \
                                             \
    COSLayoutRule *rule =                    \
    [COSLayoutRule layoutRuleWithView:_view  \
        name:name                            \
        coord:_##var                         \
        dir:COSLayoutDir##dir_];             \
                                             \
    [self.ruleHub dir_##AddRule:rule];       \
} while (0)

#define COSLAYOUT_ADD_TRANS_RULE(var, dst, exp)                 \
do {                                                            \
    COSCoord *c = _##var = (var);                               \
    self.dst = c ? COSCOORD_MAKE(c.dependencies, (exp)) : nil;  \
} while (0)

#define COSLAYOUT_ADD_BOUND_RULE(var, dir_)  \
do {                                         \
    _##var = (var);                          \
    NSString *name = @(#var);                \
                                             \
    COSLayoutRule *rule =                    \
    [COSLayoutRule layoutRuleWithView:_view  \
        name:name                            \
        coord:_##var                         \
        dir:COSLayoutDir##dir_];             \
                                             \
    self.ruleMap[name] = rule;               \
} while (0)

NS_INLINE
void cos_initialize_layout_if_needed(UIView *view) {
    Class class = [view class];

    if ([swizzledLayoutClasses containsObject:class]) return;

    SEL name = @selector(didMoveToSuperview);

    IMP origImp = class_getMethodImplementation(class, name);
    IMP overImp = imp_implementationWithBlock(^(UIView *view) {
        ((void(*)(id, SEL))(origImp))(view, name);

        COSLayout *layout = objc_getAssociatedObject(view, COSLayoutKey);

        if (layout) [layout updateLayoutDriver];
    });

    class_replaceMethod(class, name, overImp, "v@:");
    
    [swizzledLayoutClasses addObject:class];
}

NS_INLINE
void cos_initialize_driver_if_needed(UIView *view) {
    Class class = [view class];

    if ([swizzledDriverClasses containsObject:class]) return;

    SEL name = @selector(layoutSubviews);

    IMP origImp = class_getMethodImplementation(class, name);
    IMP overImp = imp_implementationWithBlock(^(UIView *view) {
        COSLayoutDriver *driver = objc_getAssociatedObject(view, COSLayoutDriverKey);

        if (driver) {
            [driver beginSolves];
            ((void(*)(id, SEL))(origImp))(view, name);
            [driver endSolves];
        } else {
            ((void(*)(id, SEL))(origImp))(view, name);
        }
    });

    class_replaceMethod(class, name, overImp, "v@:");

    [swizzledDriverClasses addObject:class];
}


#define COS_COORD_NAME(coord) \
    [NSString stringWithCString:(coord) encoding:NSASCIIStringEncoding]


@implementation COSLayout

+ (void)initialize {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        swizzledDriverClasses = [[NSMutableSet alloc] init];
        swizzledLayoutClasses = [[NSMutableSet alloc] init];
    });
}

+ (instancetype)layoutOfView:(UIView *)view {
    if (![view isKindOfClass:[UIView class]]) return nil;

    COSLayout *layout = objc_getAssociatedObject(view, COSLayoutKey);

    if (!layout) {
        layout = [[COSLayout alloc] initWithView:view];

        objc_setAssociatedObject(view, COSLayoutKey, layout, OBJC_ASSOCIATION_RETAIN);

        cos_initialize_layout_if_needed(view);

        [layout updateLayoutDriver];
    }

    return layout;
}

- (instancetype)initWithView:(UIView *)view {
    self = [super init];

    if (self) {
        _view = view;
    }

    return self;
}

- (void)addRule:(NSString *)format, ... {
    va_list argv;
    va_start(argv, format);

    [self addRule:format args:argv];

    va_end(argv);
}

- (void)addRule:(NSString *)format args:(va_list)args {
    va_list argv;
    va_copy(argv, args);

    NSArray *subRules = [format componentsSeparatedByString:@","];

    for (NSString *subRule in subRules) {
        COSLAYOUT_AST *ast = NULL;

        char *expr = (char *)[subRule cStringUsingEncoding:NSASCIIStringEncoding];

        int result = coslayout_parse_rule(expr, &ast);

        switch (result) {
        case 0: {
            NSMutableSet *keeper = [NSMutableSet set];

            [self parseAst:ast parent:NULL withArgv:&argv keeper:keeper];

            coslayout_destroy_ast(ast);
        }
            break;

        case 1: {
            [NSException raise:COSLayoutSyntaxExceptionName format:@"%@", COSLayoutSyntaxExceptionDesc];
        }
            break;

        default:
            goto end;
        }
    }

    end:
    va_end(argv);
}

- (void)parseAst:(COSLAYOUT_AST *)ast parent:(COSLAYOUT_AST *)parent withArgv:(va_list *)argv keeper:(NSMutableSet *)keeper {
    if (ast == NULL) return;

    [self parseAst:ast->l parent:ast withArgv:argv keeper:keeper];
    [self parseAst:ast->r parent:ast withArgv:argv keeper:keeper];

    switch (ast->node_type) {
    case COSLAYOUT_TOKEN_ATTR: {
        if (parent != NULL &&
            parent->node_type == '=' &&
            parent->l == ast) break;

        COSCoord *coord = [self valueForKey:COS_COORD_NAME(ast->value.coord)];

        if (!coord) {
            coord = [COSCoord coordWithFloat:0];
            [keeper addObject:coord];
        }

        ast->data = (__bridge void *)(coord);
    }
        break;

    case COSLAYOUT_TOKEN_NUMBER: {
        COSCoord *coord = [COSCoord coordWithFloat:ast->value.number];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case COSLAYOUT_TOKEN_PERCENTAGE: {
        COSCoord *coord = [COSCoord coordWithPercentage:ast->value.percentage];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case COSLAYOUT_TOKEN_COORD: {
        COSCoord *coord = nil;
        char *format = ast->value.coord;
        char *spec = format + 1;

        if (format[0] == '%') {
            if (COS_STREQ(spec, "f")) {
                coord = [COSCoord coordWithFloat:va_arg(*argv, double)];
            } else if (COS_STREQ(spec, "p")) {
                coord = [COSCoord coordWithPercentage:va_arg(*argv, double)];
            } else {
                COSCoords *coords = [COSCoords coordsOfView:va_arg(*argv, UIView *)];
                coord = [coords valueForKey:COS_COORD_NAME(spec)];
            }
        } else {
            COSFloatBlock block = va_arg(*argv, COSFloatBlock);

            if (COS_STREQ(spec, "f")) {
                coord = [COSCoord coordWithBlock:^float(COSLayoutRule *rule) {
                    return block(rule.view);
                }];
            } else {
                coord = [COSCoord coordWithBlock:^float(COSLayoutRule *rule) {
                    float percentage = block(rule.view);
                    COSCoord *coord = [COSCoord coordWithPercentage:percentage];

                    return coord.block(rule);
                }];
            }
        }

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case '+': {
        COSCoord *coord1 = (__bridge COSCoord *)(ast->l->data);
        COSCoord *coord2 = (__bridge COSCoord *)(ast->r->data);

        COSCoord *coord = [coord1 add:coord2];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case '-': {
        COSCoord *coord1 = (__bridge COSCoord *)(ast->l->data);
        COSCoord *coord2 = (__bridge COSCoord *)(ast->r->data);

        COSCoord *coord = [coord1 sub:coord2];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case '*': {
        COSCoord *coord1 = (__bridge COSCoord *)(ast->l->data);
        COSCoord *coord2 = (__bridge COSCoord *)(ast->r->data);

        COSCoord *coord = [coord1 mul:coord2];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case '/': {
        COSCoord *coord1 = (__bridge COSCoord *)(ast->l->data);
        COSCoord *coord2 = (__bridge COSCoord *)(ast->r->data);

        COSCoord *coord = [coord1 div:coord2];

        ast->data = (__bridge void *)(coord);

        [keeper addObject:coord];
    }
        break;

    case '=': {
        COSCoord *coord = (__bridge COSCoord *)(ast->r->data);

        [self setValue:coord forKey:COS_COORD_NAME(ast->l->value.coord)];

        ast->data = (__bridge void *)(coord);
    }
        break;

    default:
        break;
    }
}

- (void)updateLayoutDriver {
    UIView *superview = _view.superview;

    if (superview && !objc_getAssociatedObject(superview, COSLayoutDriverKey)) {
        COSLayoutDriver *driver = [[COSLayoutDriver alloc] initWithView:superview];

        objc_setAssociatedObject(superview, COSLayoutDriverKey, driver, OBJC_ASSOCIATION_RETAIN);
        cos_initialize_driver_if_needed(superview);
    }
}

- (NSSet *)dependencies {
    NSMutableSet *set = [[NSMutableSet alloc] init];

    for (COSLayoutRule *rule in _ruleHub.vRules) {
        [set unionSet:rule.coord.dependencies];
    }

    for (COSLayoutRule *rule in _ruleHub.hRules) {
        [set unionSet:rule.coord.dependencies];
    }

    for (COSLayoutRule *rule in [_ruleMap allValues]) {
        [set unionSet:rule.coord.dependencies];
    }

    if ([set containsObject:COS_SUPERVIEW_PLACEHOLDER]) {
        [set removeObject:COS_SUPERVIEW_PLACEHOLDER];

        if (_view.superview) {
            [set addObject:_view.superview];
        }
    }

    return set;
}

- (void)solveRules:(NSArray *)rules {
    COSLayoutRulesSolver *solver = [[COSLayoutRulesSolver alloc] init];

    solver.view = _view;

    NSMutableString *selStr = [NSMutableString stringWithString:@"solve"];

    for (COSLayoutRule *rule in rules) {
        [selStr appendString:[rule.name capitalizedString]];
    }

    [selStr appendString:@":"];

    SEL sel = NSSelectorFromString(selStr);
    CGRect (*imp)(id, SEL, NSArray *) = (void *)[solver methodForSelector:sel];

    _frame = imp(solver, sel, rules);

    [self checkBounds];
}

- (void)checkBounds {
    CGSize size = _frame.size;

    CGFloat minw = COS_MM_RAW_VALUE(self, minw);

    if (COS_VALID_DIM(minw) && size.width < minw) {
        size.width = minw;
    }

    CGFloat maxw = COS_MM_RAW_VALUE(self, maxw);

    if (COS_VALID_DIM(maxw) && size.width > maxw) {
        size.width = maxw;
    }

    CGFloat minh = COS_MM_RAW_VALUE(self, minh);

    if (COS_VALID_DIM(minh) && size.height < minh) {
        size.height = minh;
    }

    CGFloat maxh = COS_MM_RAW_VALUE(self, maxh);

    if (COS_VALID_DIM(maxh) && size.height > maxh) {
        size.height = maxh;
    }

    _frame.size = size;
}

- (void)startLayout {
    _frame = _view.frame;

    [self checkBounds];

    if ([_ruleHub.vRules count]) {
        [self solveRules:_ruleHub.vRules];
    }

    if ([_ruleHub.hRules count]) {
        [self solveRules:_ruleHub.hRules];
    }

    [self checkBounds];

    if (!CGRectEqualToRect(_frame, _view.frame)) {
        _view.frame = _frame;
    }
}

- (void)setMinw:(COSCoord *)minw {
    COSLAYOUT_ADD_BOUND_RULE(minw, h);
}

- (void)setMaxw:(COSCoord *)maxw {
    COSLAYOUT_ADD_BOUND_RULE(maxw, h);
}

- (void)setMinh:(COSCoord *)minh {
    COSLAYOUT_ADD_BOUND_RULE(minh, v);
}

- (void)setMaxh:(COSCoord *)maxh {
    COSLAYOUT_ADD_BOUND_RULE(maxh, v);
}

- (void)setTt:(COSCoord *)tt {
    COSLAYOUT_ADD_RULE(tt, v);
}

- (void)setTb:(COSCoord *)tb {
    COSLAYOUT_ADD_TRANS_RULE(tb, tt, COS_SUPERVIEW_HEIGHT - tb.block(rule));
}

- (void)setLl:(COSCoord *)ll {
    COSLAYOUT_ADD_RULE(ll, h);
}

- (void)setLr:(COSCoord *)lr {
    COSLAYOUT_ADD_TRANS_RULE(lr, ll, COS_SUPERVIEW_WIDTH - lr.block(rule));
}

- (void)setBb:(COSCoord *)bb {
    COSLAYOUT_ADD_TRANS_RULE(bb, bt, COS_SUPERVIEW_HEIGHT - bb.block(rule));
}

- (void)setBt:(COSCoord *)bt {
    COSLAYOUT_ADD_RULE(bt, v);
}

- (void)setRr:(COSCoord *)rr {
    COSLAYOUT_ADD_TRANS_RULE(rr, rl, COS_SUPERVIEW_WIDTH - rr.block(rule));
}

- (void)setRl:(COSCoord *)rl {
    COSLAYOUT_ADD_RULE(rl, h);
}

- (void)setCt:(COSCoord *)ct {
    COSLAYOUT_ADD_RULE(ct, v);
}

- (void)setCl:(COSCoord *)cl {
    COSLAYOUT_ADD_RULE(cl, h);
}

- (void)setCb:(COSCoord *)cb {
    COSLAYOUT_ADD_TRANS_RULE(cb, ct, COS_SUPERVIEW_HEIGHT - cb.block(rule));
}

- (void)setCr:(COSCoord *)cr {
    COSLAYOUT_ADD_TRANS_RULE(cr, cl, COS_SUPERVIEW_WIDTH - cr.block(rule));
}

- (COSLayoutRuleHub *)ruleHub {
    return (_ruleHub ?: (_ruleHub = [[COSLayoutRuleHub alloc] init]));
}

- (NSMutableDictionary *)ruleMap {
    return (_ruleMap ?: (_ruleMap = [[NSMutableDictionary alloc] init]));
}

@end


#define COSCOORD_CALC(expr)                          \
do {                                                 \
    COSCoord *coord = [[COSCoord alloc] init];       \
    NSMutableSet *dependencies = self.dependencies;  \
                                                     \
    [dependencies unionSet:other.dependencies];      \
                                                     \
    coord.dependencies = dependencies;               \
    coord.block = ^float(COSLayoutRule *rule) {      \
        return (expr);                               \
    };                                               \
                                                     \
    return coord;                                    \
} while (0)


@implementation COSCoord

+ (instancetype)coordWithFloat:(float)value {
    COSCoord *coord = [[COSCoord alloc] init];

    coord.block = ^float(COSLayoutRule *rule) {
        return value;
    };

    return coord;
}

+ (instancetype)coordWithPercentage:(float)percentage {
    COSCoord *coord = [[COSCoord alloc] init];

    percentage /= 100.0f;

    coord.block = ^float(COSLayoutRule *rule) {
        UIView *view = rule.view;
        CGFloat size = (rule.dir == COSLayoutDirv ? COS_SUPERVIEW_HEIGHT : COS_SUPERVIEW_WIDTH);

        return size * percentage;
    };

    return coord;
}

+ (instancetype)coordWithBlock:(COSCoordBlock)block {
    COSCoord *coord = [[COSCoord alloc] init];

    coord.block = block;

    return coord;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _dependencies = [NSMutableSet setWithObject:COS_SUPERVIEW_PLACEHOLDER];
    }

    return self;
}

- (instancetype)add:(COSCoord *)other {
    COSCOORD_CALC(self.block(rule) + other.block(rule));
}

- (instancetype)sub:(COSCoord *)other {
    COSCOORD_CALC(self.block(rule) - other.block(rule));
}

- (instancetype)mul:(COSCoord *)other {
    COSCOORD_CALC(self.block(rule) * other.block(rule));
}

- (instancetype)div:(COSCoord *)other {
    COSCOORD_CALC(self.block(rule) / other.block(rule));
}

- (NSMutableSet *)dependencies {
    return _dependencies ?: (_dependencies = [[NSMutableSet alloc] init]);
}

@end


@interface COSCoords ()

@property (nonatomic, weak) UIView *view;

@property (nonatomic, strong) COSCoord *w;
@property (nonatomic, strong) COSCoord *h;

@property (nonatomic, strong) COSCoord *tt;
@property (nonatomic, strong) COSCoord *tb;

@property (nonatomic, strong) COSCoord *ll;
@property (nonatomic, strong) COSCoord *lr;

@property (nonatomic, strong) COSCoord *bb;
@property (nonatomic, strong) COSCoord *bt;

@property (nonatomic, strong) COSCoord *rr;
@property (nonatomic, strong) COSCoord *rl;

@property (nonatomic, strong) COSCoord *ct;
@property (nonatomic, strong) COSCoord *cl;
@property (nonatomic, strong) COSCoord *cb;
@property (nonatomic, strong) COSCoord *cr;

- (instancetype)initWithView:(UIView *)view;

@end


#define COS_VIEW_TOP    ([view convertRect:view.bounds toView:rule.view.superview].origin.y)
#define COS_VIEW_LEFT   ([view convertRect:view.bounds toView:rule.view.superview].origin.x)
#define COS_VIEW_WIDTH  (view.bounds.size.width)
#define COS_VIEW_HEIGHT (view.bounds.size.height)

#define LAZY_LOAD_COORD(ivar, expr) \
    (ivar ?: (ivar = COSCOORD_MAKE([NSMutableSet setWithObject:_view], expr)))


@implementation COSCoords

+ (instancetype)coordsOfView:(UIView *)view {
    static const void *coordsKey = &coordsKey;

    if (![view isKindOfClass:[UIView class]]) {
        return nil;
    }

    COSCoords *coords = objc_getAssociatedObject(view, coordsKey);

    if (!coords) {
        coords = [[COSCoords alloc] initWithView:view];

        objc_setAssociatedObject(view, coordsKey, coords, OBJC_ASSOCIATION_RETAIN);
    }

    return coords;
}

- (instancetype)initWithView:(UIView *)view {
    self = [super init];

    if (self) {
        _view = view;
    }

    return self;
}

- (COSCoord *)tt {
    return LAZY_LOAD_COORD(_tt, COS_VIEW_TOP);
}

- (COSCoord *)tb {
    return LAZY_LOAD_COORD(_tb, COS_SUPERVIEW_HEIGHT - COS_VIEW_TOP);
}

- (COSCoord *)ll {
    return LAZY_LOAD_COORD(_ll, COS_VIEW_LEFT);
}

- (COSCoord *)lr {
    return LAZY_LOAD_COORD(_lr, COS_SUPERVIEW_WIDTH - COS_VIEW_LEFT);
}

- (COSCoord *)bb {
    return LAZY_LOAD_COORD(_bb, COS_SUPERVIEW_HEIGHT - COS_VIEW_TOP - COS_VIEW_HEIGHT);
}

- (COSCoord *)bt {
    return LAZY_LOAD_COORD(_bt, COS_VIEW_TOP + COS_VIEW_HEIGHT);
}

- (COSCoord *)rr {
    return LAZY_LOAD_COORD(_rr, COS_SUPERVIEW_WIDTH - COS_VIEW_LEFT - COS_VIEW_WIDTH);
}

- (COSCoord *)rl {
    return LAZY_LOAD_COORD(_rl, COS_VIEW_LEFT + COS_VIEW_WIDTH);
}

- (COSCoord *)ct {
    return LAZY_LOAD_COORD(_ct, COS_VIEW_TOP + COS_VIEW_HEIGHT / 2);
}

- (COSCoord *)cl {
    return LAZY_LOAD_COORD(_cl, COS_VIEW_LEFT + COS_VIEW_WIDTH / 2);
}

- (COSCoord *)cb {
    return LAZY_LOAD_COORD(_cb, COS_SUPERVIEW_HEIGHT - COS_VIEW_TOP - COS_VIEW_HEIGHT / 2);
}

- (COSCoord *)cr {
    return LAZY_LOAD_COORD(_cr, COS_SUPERVIEW_WIDTH - COS_VIEW_LEFT - COS_VIEW_WIDTH / 2);
}

- (COSCoord *)w {
    return LAZY_LOAD_COORD(_w, COS_VIEW_WIDTH);
}

- (COSCoord *)h {
    return LAZY_LOAD_COORD(_h, COS_VIEW_HEIGHT);
}

@end


@implementation UIView (COSLayout)

- (COSLayout *)cosLayout {
    return [COSLayout layoutOfView:self];
}

@end
