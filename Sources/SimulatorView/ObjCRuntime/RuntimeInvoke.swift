import Foundation
import ObjectiveC

/// Casts a `class_getMethodImplementation` IMP to the right C calling convention so we can
/// invoke private Obj-C methods (`-foo:error:`, `+sharedFoo:error:`, etc.) without an Obj-C
/// header. The helpers below cover the variants we actually need; add more as required.
///
/// Derived from baguette (Apache 2.0).
enum RuntimeInvoke {
    static func instanceWithError<Result>(
        _ target: NSObject,
        _ selector: Selector,
        _ error: inout NSError?,
        returning _: Result.Type = Result.self
    ) -> Result? where Result: AnyObject {
        guard let imp = class_getMethodImplementation(type(of: target), selector) else { return nil }
        typealias Fn = @convention(c) (
            AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> AnyObject?
        return unsafeBitCast(imp, to: Fn.self)(target, selector, &error) as? Result
    }

    static func instanceWithArgAndError<Result>(
        _ target: NSObject,
        _ selector: Selector,
        _ arg: AnyObject,
        _ error: inout NSError?,
        returning _: Result.Type = Result.self
    ) -> Result? where Result: AnyObject {
        guard let imp = class_getMethodImplementation(type(of: target), selector) else { return nil }
        typealias Fn = @convention(c) (
            AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> AnyObject?
        return unsafeBitCast(imp, to: Fn.self)(target, selector, arg, &error) as? Result
    }

    static func classWithArgAndError<Result>(
        _ cls: AnyClass,
        _ selector: Selector,
        _ arg: AnyObject,
        _ error: inout NSError?,
        returning _: Result.Type = Result.self
    ) -> Result? where Result: AnyObject {
        guard let metaCls = object_getClass(cls),
              let imp = class_getMethodImplementation(metaCls, selector) else { return nil }
        typealias Fn = @convention(c) (
            AnyClass, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> AnyObject?
        return unsafeBitCast(imp, to: Fn.self)(cls, selector, arg, &error) as? Result
    }
}

func dlerrorString() -> String {
    guard let raw = dlerror() else { return "(no dlerror)" }
    return String(cString: raw)
}
