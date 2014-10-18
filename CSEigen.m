// CSEigen.m
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

#import "CSEigen.h"
#import <objc/runtime.h>
#import <libkern/OSAtomic.h>


@interface CSEigen ()

@property (atomic, weak) Class eigenClass;
@property (atomic, assign) OSSpinLock *disposingLock;

@end


static SEL deallocSel = NULL;
static const void *classKey = &classKey;

static inline Class cs_class(id self, SEL _cmd) {
    return objc_getAssociatedObject(self, classKey);
}

static inline Class cs_create_eigen_class(NSObject *object) {
    char *clsname = NULL;

    asprintf(&clsname, "CSEigen_%s_%p_%u", class_getName([object class]), object, arc4random());

    Class eigen = objc_allocateClassPair(object_getClass(object), clsname, 0);

    free(clsname);

    if (eigen == Nil) return cs_create_eigen_class(object);

    objc_registerClassPair(eigen);

    class_addMethod(eigen, @selector(class), (IMP)cs_class, "#@:");

    return eigen;
}

static inline void cs_dispose_eigen_class(Class eigenClass) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(eigenClass, &count);

    for (int i = 0; i < count; i++) {
        imp_removeBlock(method_getImplementation(methods[i]));
    }

    objc_disposeClassPair(eigenClass);

    free(methods);
}


@implementation CSEigen

+ (void)initialize {
    deallocSel = NSSelectorFromString(@"dealloc");
}

+ (instancetype)eigenOfObject:(NSObject *)object {
    CSEigen *eigen = nil;

    if (object) {
        static const void *eigenKey = &eigenKey;

        eigen = objc_getAssociatedObject(object, eigenKey);

        if (!eigen) {
            eigen = [[CSEigen alloc] init];
            Class eigenClass = cs_create_eigen_class(object);

            eigen.eigenClass = eigenClass;

            objc_setAssociatedObject(object, classKey, [object class], OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(object, eigenKey, eigen, OBJC_ASSOCIATION_RETAIN);
            
            object_setClass(object, eigenClass);
        }
    }

    return eigen;
}

- (void)setMethod:(SEL)name types:(const char *)types block:(id)block {
    IMP imp = class_getMethodImplementation(self.eigenClass, name);

    if (imp) imp_removeBlock(imp);

    if (sel_isEqual(name, deallocSel)) {
        OSSpinLock *disposingLock = _disposingLock;

        if (!disposingLock) {
            disposingLock = (OSSpinLock *)malloc(sizeof(OSSpinLock));
            *disposingLock = OS_SPINLOCK_INIT;
            _disposingLock = disposingLock;
        }

        imp = imp_implementationWithBlock(^(id object) {
            OSSpinLockLock(disposingLock);
            ((void(^)(id))block)(object);
            OSSpinLockUnlock(disposingLock);
        });
    } else {
        imp = imp_implementationWithBlock(block);
    }

    class_replaceMethod(self.eigenClass, name, imp, types);
}

- (CSIMP)superImp:(SEL)name {
    return (CSIMP)class_getMethodImplementation(class_getSuperclass(self.eigenClass), name);
}

- (void)dealloc {
    Class eigenClass = self.eigenClass;
    OSSpinLock *disposingLock = self.disposingLock;

    if (disposingLock) {
        dispatch_queue_t queue = [NSThread isMainThread] ?
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) :
        dispatch_get_main_queue();

        dispatch_async(queue, ^{
            OSSpinLockLock(disposingLock);
            cs_dispose_eigen_class(eigenClass);
            OSSpinLockUnlock(disposingLock);

            free(disposingLock);
        });
    } else {
        cs_dispose_eigen_class(eigenClass);
    }
}

@end