// pwneovide-set-default: make PWNeovide the default handler for content types.
//
// LSHandlerRank in Info.plist only decides who is *eligible* and how the
// "Open With" submenu is ordered. Once a default has been recorded for a type —
// either by the user picking one, or by whichever app happened to register
// first — that recorded choice wins regardless of rank. This tool overwrites
// the recorded choice.
//
// With no arguments it claims the full set of types the bundle declares at
// Owner rank; pass UTIs explicitly to claim only those, e.g.
//
//     pwneovide-set-default net.daringfireball.markdown
//
// Requires -fobjc-arc (see flake.nix).
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

static NSString *const kBundleID = @"com.zmre.pwneovide";

// Mirrors the Owner-rank LSItemContentTypes claims in extras/Info.plist.
static NSArray<NSString *> *DefaultContentTypes(void) {
    return @[
        @"net.daringfireball.markdown",
        @"public.plain-text",
        @"public.utf8-plain-text",
        @"public.utf16-plain-text",
        @"public.utf16-external-plain-text",
        @"public.log",
        @"org.ledger-cli.journal",
        @"io.mermaid.diagram",
        @"org.asciidoc.document",
        @"org.restructuredtext.document",
        @"org.orgmode.document",
        @"app.typst.source",
        @"com.zmre.pwneovide.text",
        @"public.source-code",
        @"public.script",
        @"public.shell-script",
        @"public.json",
        @"public.yaml",
        @"org.tomlang.toml",
        @"org.nixos.nix",
        @"public.comma-separated-values-text",
        @"public.tab-separated-values-text",
        @"public.delimited-values-text",
    ];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *types;
        if (argc > 1) {
            NSMutableArray<NSString *> *requested = [NSMutableArray array];
            for (int i = 1; i < argc; i++) {
                [requested addObject:@(argv[i])];
            }
            types = requested;
        } else {
            types = DefaultContentTypes();
        }

        int failures = 0;
        for (NSString *type in types) {
            // LSSetDefaultRoleHandlerForContentType is deprecated in favour of
            // -[NSWorkspace setDefaultApplicationAtURL:toOpenContentType:...],
            // but that requires a resolvable UTType instance, which does not
            // exist for types no app has registered yet — exactly the case we
            // need to handle on a first run. The old call takes a bare
            // identifier string and still works.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            OSStatus status = LSSetDefaultRoleHandlerForContentType(
                (__bridge CFStringRef)type, kLSRolesAll,
                (__bridge CFStringRef)kBundleID);
#pragma clang diagnostic pop

            if (status == noErr) {
                printf("  ok    %s\n", type.UTF8String);
            } else {
                printf("  FAIL  %s (OSStatus %d)\n", type.UTF8String, (int)status);
                failures++;
            }
        }

        if (failures > 0) {
            fprintf(stderr,
                    "\n%d type(s) failed. Is the bundle registered? Run "
                    "pwneovide-register first.\n", failures);
            return 1;
        }
        printf("\nClaimed %lu content type(s) for %s.\n",
               (unsigned long)types.count, kBundleID.UTF8String);
        return 0;
    }
}
