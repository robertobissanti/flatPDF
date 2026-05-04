#include "MacAbout.h"

#import <Cocoa/Cocoa.h>

void showNativeAboutPanel()
{
    @autoreleasepool {
        NSString* creditsText = @"© 2025-2026 Roberto Bissanti\nroberto.bissanti@gmail.com\nLicenza GPL v2";
        NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
        [paragraph setAlignment:NSTextAlignmentCenter];

        NSDictionary* attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [NSColor labelColor],
            NSParagraphStyleAttributeName: paragraph
        };

        NSAttributedString* credits = [[NSAttributedString alloc] initWithString:creditsText
                                                                       attributes:attributes];

        NSDictionary* options = @{
            NSAboutPanelOptionApplicationName: @"flatPDF",
            NSAboutPanelOptionApplicationVersion: @"0.1",
            NSAboutPanelOptionCredits: credits
        };

        [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:options];
    }
}
