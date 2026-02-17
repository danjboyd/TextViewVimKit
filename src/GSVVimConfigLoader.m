#import "GSVVimConfigLoader.h"

static NSString * const GSVDefaultInternalConfigPath = @"~/.gnustepvimrc";
static NSString * const GSVDefaultVimrcPath = @"~/.vimrc";

static NSArray *GSVTokenizeByWhitespace(NSString *line)
{
    NSMutableArray *tokens = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:line];
    while (![scanner isAtEnd]) {
        (void)[scanner scanCharactersFromSet:whitespace intoString:NULL];
        NSString *token = nil;
        if (![scanner scanUpToCharactersFromSet:whitespace intoString:&token]) {
            break;
        }
        if (token != nil && [token length] > 0) {
            [tokens addObject:token];
        }
    }
    return tokens;
}

static BOOL GSVLooksLikeCommentOrBlank(NSString *line)
{
    if (line == nil) {
        return YES;
    }
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
        return YES;
    }
    if ([trimmed hasPrefix:@"\""]) {
        return YES;
    }
    return NO;
}

static NSString *GSVCanonicalizeEscToken(NSString *value)
{
    if (value == nil) {
        return nil;
    }
    if ([[value lowercaseString] isEqualToString:@"<esc>"]) {
        return @"<Esc>";
    }
    return nil;
}

static BOOL GSVIsSupportedLHS(NSString *lhs)
{
    if (lhs == nil || [lhs length] == 0) {
        return NO;
    }
    NSCharacterSet *disallowed = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange whitespaceRange = [lhs rangeOfCharacterFromSet:disallowed];
    if (whitespaceRange.location != NSNotFound) {
        return NO;
    }
    return YES;
}

static BOOL GSVParseClipboardOptionToken(NSString *token, BOOL *unnamedRegisterUsesSystemClipboard)
{
    if (token == nil || unnamedRegisterUsesSystemClipboard == NULL) {
        return NO;
    }

    NSString *lower = [token lowercaseString];
    if ([lower isEqualToString:@"noclipboard"] ||
        [lower isEqualToString:@"clipboard&"] ||
        [lower isEqualToString:@"clipboard<"]) {
        *unnamedRegisterUsesSystemClipboard = NO;
        return YES;
    }

    NSString *prefix = @"clipboard=";
    if (![lower hasPrefix:prefix]) {
        return NO;
    }

    NSString *value = [lower substringFromIndex:[prefix length]];
    if ([value length] == 0) {
        *unnamedRegisterUsesSystemClipboard = NO;
        return YES;
    }

    NSArray *items = [value componentsSeparatedByString:@","];
    BOOL enabled = NO;
    for (NSString *item in items) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed length] == 0) {
            continue;
        }
        if ([trimmed isEqualToString:@"unnamed"] || [trimmed isEqualToString:@"unnamedplus"]) {
            enabled = YES;
            continue;
        }
        return NO;
    }

    *unnamedRegisterUsesSystemClipboard = enabled;
    return YES;
}

static void GSVApplyConfigFile(NSString *path,
                               NSString *sourceLabel,
                               NSMutableDictionary *insertMappings,
                               NSMutableArray *diagnostics,
                               BOOL *unnamedRegisterUsesSystemClipboard)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (path == nil || ![fileManager fileExistsAtPath:path]) {
        return;
    }

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (contents == nil) {
        [diagnostics addObject:[NSString stringWithFormat:@"%@: failed to read file (%@)", sourceLabel, [error localizedDescription]]];
        return;
    }

    NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger lineNumber = 0;
    for (NSString *line in lines) {
        lineNumber += 1;
        if (GSVLooksLikeCommentOrBlank(line)) {
            continue;
        }

        NSArray *tokens = GSVTokenizeByWhitespace(line);
        if ([tokens count] == 0) {
            continue;
        }

        NSString *command = [[tokens objectAtIndex:0] lowercaseString];
        if ([command isEqualToString:@"set"]) {
            if ([tokens count] < 2) {
                [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu invalid set directive",
                                                                 sourceLabel,
                                                                 (unsigned long)lineNumber]];
                continue;
            }
            for (NSUInteger i = 1; i < [tokens count]; i += 1) {
                NSString *token = [tokens objectAtIndex:i];
                BOOL parsed = GSVParseClipboardOptionToken(token, unnamedRegisterUsesSystemClipboard);
                if (!parsed) {
                    [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu unsupported set option: %@",
                                                                     sourceLabel,
                                                                     (unsigned long)lineNumber,
                                                                     token]];
                }
            }
            continue;
        }

        if (![command isEqualToString:@"inoremap"] && ![command isEqualToString:@"inoremap!"]) {
            [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu unsupported directive: %@",
                                                             sourceLabel,
                                                             (unsigned long)lineNumber,
                                                             [tokens objectAtIndex:0]]];
            continue;
        }

        if ([tokens count] < 3) {
            [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu invalid inoremap (expected: inoremap <lhs> <rhs>)",
                                                             sourceLabel,
                                                             (unsigned long)lineNumber]];
            continue;
        }

        NSString *lhs = [tokens objectAtIndex:1];
        NSString *rhs = [tokens objectAtIndex:2];
        if (!GSVIsSupportedLHS(lhs)) {
            [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu unsupported inoremap lhs: %@",
                                                             sourceLabel,
                                                             (unsigned long)lineNumber,
                                                             lhs]];
            continue;
        }

        NSString *normalizedRHS = GSVCanonicalizeEscToken(rhs);
        if (normalizedRHS == nil) {
            [diagnostics addObject:[NSString stringWithFormat:@"%@:%lu unsupported inoremap rhs: %@",
                                                             sourceLabel,
                                                             (unsigned long)lineNumber,
                                                             rhs]];
            continue;
        }

        [insertMappings setObject:normalizedRHS forKey:lhs];
    }
}

@implementation GSVVimConfigLoader

+ (GSVVimConfig *)loadDefaultConfig
{
    return [self loadConfigWithInternalConfigPath:GSVDefaultInternalConfigPath
                                        vimrcPath:GSVDefaultVimrcPath];
}

+ (GSVVimConfig *)loadConfigWithInternalConfigPath:(NSString *)internalConfigPath
                                         vimrcPath:(NSString *)vimrcPath
{
    NSString *expandedInternalPath = [internalConfigPath stringByExpandingTildeInPath];
    NSString *expandedVimrcPath = [vimrcPath stringByExpandingTildeInPath];

    NSMutableDictionary *insertMappings = [NSMutableDictionary dictionary];
    NSMutableArray *diagnostics = [NSMutableArray array];
    BOOL unnamedRegisterUsesSystemClipboard = NO;

    // Lower-priority compatibility layer first.
    GSVApplyConfigFile(expandedVimrcPath,
                       @".vimrc",
                       insertMappings,
                       diagnostics,
                       &unnamedRegisterUsesSystemClipboard);
    // Internal config supersedes imported .vimrc entries.
    GSVApplyConfigFile(expandedInternalPath,
                       @".gnustepvimrc",
                       insertMappings,
                       diagnostics,
                       &unnamedRegisterUsesSystemClipboard);

    return [[GSVVimConfig alloc] initWithInsertModeMappings:insertMappings
                                                diagnostics:diagnostics
                                unnamedRegisterUsesSystemClipboard:unnamedRegisterUsesSystemClipboard];
}

@end
