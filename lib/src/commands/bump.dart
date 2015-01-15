
library den.src.commands.bump;

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:unscripted/unscripted.dart';

import '../bump.dart';
import '../git.dart';
import '../pub.dart';
import '../theme.dart';
import '../util.dart';

class BumpCommand {
  @ArgExample('1.2.3', help: 'Exact version')
  @ArgExample('patch', help: '1.2.3 -> 1.2.4')
  @ArgExample('minor --pre', help: '1.2.3 -> 1.3.0-0')
  @ArgExample('major --pre-id beta', help: '1.2.3 -> 2.0.0-beta.0')
  @ArgExample('breaking', help: 'A breaking change.')
  @ArgExample('release --pre', help: '1.0.0-dev.2 -> 1.0.0-dev.3')
  @ArgExample('release', help: '1.0.0-dev.2 -> 1.0.0')
  @ArgExample('minor -m "Bump to {v} for ..."', help: 'Custom commit message')
  @SubCommand(help: '''
Bump the pubspec version.

If run in a git repo it also creates a version commit and tag, and fails if 
the repo is not clean.  The --message option can be used to customize the 
commit message.''')
  bump(
      @Positional(allowed: _getAllowedReleaseTypes, parser: _parseBumpStrategy,
          help: '''
 Either an exact version e.g. 1.2.3-dev, or one of the
               following release types:

  [major]      Major release.
  [minor]      Minor release.
  [patch]      Patch release.
  [breaking]   Breaking release ([minor] if <1.0.0, [major] otherwise).
  [release]    Remove or increment (when using --pre or --pre-id)
               a pre-release.  Same as [patch], but fails if not currently 
               on a pre-release.)
  [build]      Increment or initialize (to 1) the build number.
               (Cannot be used with --pre or --pre-id)

               Use --pre or --pre-id to pre-release this type.

               [major], [minor], and [patch], if currently on a 
               pre-release of that type, are equivalent to [release]
               (removes or increments (when using --pre or --pre-id)
               the pre-release).''')
      strategy,
      {@Flag(help: """
Do a pre-release.  If already on an <n> or <id>.<n> 
pre-relase where <n> is an integer and <id> is a String, 
increments <n>.  If not on a pre-release, initializes it 
to "0".  Otherwise fails.""")
       bool pre: false,
       @Option(help: """
Do a pre-release with an id e.g. "beta".  If already on an 
<id>.<n> pre-relase where <n> is an integer and <id> equals 
<pre id>, increments <n>.  Otherwise initializes it to 
<pre id>.0.""")
       String preId,
       @Option(abbr: "m", defaultsTo: "v{v}", help: """
The git commit message template.  Any instance of "{v}" will 
be replaced by the new version.""")
       String message
  }) {

    var pubspec = Pubspec.load();
    var version = pubspec.version;

    Version newVersion;

    var effectivePre = preId == null ? pre : preId;

    if (strategy is Version) {
      if (strategy.isPreRelease) {
        if (false != effectivePre) {
          throw 'Cannot specify --pre or --pre-id and an exact version with a '
              'pre-release.';
        }
        newVersion = strategy;
      } else {
        List newPreRelease = createPreRelease(effectivePre);
        newVersion = withPreRelease(strategy, newPreRelease);
      }

      if (version == newVersion) {
        throw 'Cannot bump to the same version: $version';
      }
    } else {
      var releaseType = strategy as ReleaseType;
      newVersion = bumpVersion(version, releaseType, pre: effectivePre);
    }

    var packagePath = p.dirname(pubspec.path);

    shouldDoGit(packagePath).then((should) {
      pubspec.version = newVersion;
      pubspec.save();
      print(
          theme.info('Bumped version from ') +
          theme.version(version.toString()) +
          theme.info(' to ') +
          theme.version(newVersion.toString()));

      if (should) {
        return taggedVersionCommit(newVersion, packagePath, messageTemplate: message);
      }
    });
  }
}

_getAllowedReleaseTypes() => new Map.fromIterables(
    _allowedReleaseTypes.keys.map(enumName), _allowedReleaseTypes.values);

var _allowedReleaseTypes = {
  ReleaseType.major: '',
  ReleaseType.minor: '',
  ReleaseType.patch: '',
  ReleaseType.release: 'Releases a pre-release, or increments it when --pre is specified',
  ReleaseType.build: 'Adds or increments a build number',
};

_parseBumpStrategy(String s) {
  try {
    return new Version.parse(s);
  } catch (e) {
    try {
      return _parseReleaseType(s);
    } catch (e) {
      throw 'Invalid bump strategy: $s';
    }
  }
}

ReleaseType _parseReleaseType(String releaseTypeText) =>
    ReleaseType.values.firstWhere((releaseType) =>
        enumName(releaseType) == releaseTypeText, orElse: () =>
            throw 'Invalid release type "$releaseTypeText"');
