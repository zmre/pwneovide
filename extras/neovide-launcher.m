// Launcher binary for PWNeovide.app
//
// Compiled locally to get linker-signed, which macOS AMFI trusts for
// LaunchServices app launches without requiring Developer ID or notarization.
// This binary exec's the real neovide-bin sitting next to it.
//
// It does not exec immediately: when Finder is asked to open a document with
// this app, LaunchServices launches the bundle and *then* delivers the paths as
// an Apple Event (kAEOpenDocuments). Exec'ing straight out of main() would tear
// down the process image before any delegate existed to receive that event, so
// the file would be dropped and the app would open an empty buffer. Instead we
// spin up a minimal NSApplication, wait for the event, and exec neovide-bin
// with the paths appended as arguments.
//
// exec (rather than spawn) keeps the PID that LaunchServices launched, so the
// bundle identity, Dock tile and app lifecycle stay intact.
//
// Note that neovide itself also implements application:openFiles:, which is
// what handles documents opened while it is *already* running — by then this
// launcher is long gone.
//
// Requires -fobjc-arc (see flake.nix).
#import <Cocoa/Cocoa.h>
#import <mach-o/dyld.h>
#import <limits.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

// Absolute path to neovide-bin, resolved relative to this executable.
static NSString *NeovideBinPath(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) {
        return nil;
    }

    char resolved[PATH_MAX];
    if (realpath(path, resolved) == NULL) {
        return nil;
    }

    char *lastSlash = strrchr(resolved, '/');
    if (lastSlash == NULL) {
        return nil;
    }
    *lastSlash = '\0';

    return [NSString stringWithFormat:@"%s/neovide-bin", resolved];
}

// Replace this process with neovide-bin, passing `files` as the paths to open.
// Does not return unless the exec fails.
static void ExecNeovide(NSArray<NSString *> *files) {
    NSString *bin = NeovideBinPath();
    if (bin == nil) {
        fprintf(stderr, "pwneovide: could not locate neovide-bin\n");
        exit(1);
    }

    // argv[0] + one slot per file + NULL terminator.
    char **argv = calloc(files.count + 2, sizeof(char *));
    if (argv == NULL) {
        exit(1);
    }

    argv[0] = strdup(bin.fileSystemRepresentation);
    NSUInteger i = 1;
    for (NSString *file in files) {
        argv[i++] = strdup(file.fileSystemRepresentation);
    }
    argv[i] = NULL;

    execv(argv[0], argv);
    perror("pwneovide: execv");
    exit(1);
}

@interface PWNeovideLauncher : NSObject <NSApplicationDelegate>
@end

@implementation PWNeovideLauncher

// Finder "Open With", drag-onto-icon and `open -a` all arrive here. AppKit
// guarantees this runs before applicationDidFinishLaunching:, so the exec below
// wins the race against the empty-launch path.
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    ExecNeovide(filenames);
}

// Reached only on a plain launch with no document event pending.
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    ExecNeovide(@[]);
}

// Let neovim open its own empty buffer rather than having AppKit synthesise an
// untitled document for us.
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return NO;
}

@end

// NSApplication.delegate is a weak reference under ARC, so the delegate needs an
// owner that outlives the call setting it.
static PWNeovideLauncher *gDelegate = nil;

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Invoked from a shell with real arguments (or via `open --args`): there
        // is no Apple Event coming, so forward them verbatim and exec now.
        // LaunchServices on older systems tacks on a "-psn_0_12345" process
        // serial number that is not meant for neovide.
        NSMutableArray<NSString *> *forwarded = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            if (strncmp(argv[i], "-psn_", 5) == 0) {
                continue;
            }
            [forwarded addObject:@(argv[i])];
        }
        if (forwarded.count > 0) {
            ExecNeovide(forwarded);
        }

        NSApplication *app = [NSApplication sharedApplication];
        gDelegate = [[PWNeovideLauncher alloc] init];
        app.delegate = gDelegate;
        [app run];
    }
    return 0;
}
