// Launcher binary for PWNeovide.app
// Compiled locally to get linker-signed, which macOS AMFI trusts for
// LaunchServices app launches without requiring Developer ID or notarization.
// This binary exec's the real neovide-bin in the same directory.
#import <Cocoa/Cocoa.h>
#import <mach-o/dyld.h>

int main(int argc, char *argv[]) {
    char path[4096];
    uint32_t size = sizeof(path);
    _NSGetExecutablePath(path, &size);

    char resolved[4096];
    realpath(path, resolved);

    // Find the directory containing this executable
    char *lastSlash = strrchr(resolved, '/');
    if (!lastSlash) return 1;
    *lastSlash = '\0';

    char binpath[4096];
    snprintf(binpath, sizeof(binpath), "%s/neovide-bin", resolved);

    argv[0] = binpath;
    execv(binpath, argv);
    // If exec fails, exit with error
    perror("execv");
    return 1;
}
