//
//  IPWidgetBundle.swift
//  IPWidgetExtension
//
//  The extension's entry point. A `WidgetBundle` is how a single extension
//  can vend one or more widgets; here it vends just the IP widget. The
//  `@main` attribute marks this as the executable's start, replacing the
//  classic NSExtensionPrincipalClass Info.plist mechanism for SwiftUI-based
//  widgets.
//

import WidgetKit
import SwiftUI

@main
struct IPWidgetBundle: WidgetBundle {
    var body: some Widget {
        IPWidget()
    }
}
