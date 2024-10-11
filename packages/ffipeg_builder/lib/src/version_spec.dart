/// Class representing a version specifier for FFmpeg versions.
class VersionSpecifier {
  final String rawSpecifier;
  final List<VersionConstraint> constraints;

  VersionSpecifier._(this.rawSpecifier, this.constraints);

  /// Parses a [String?] into a [VersionSpecifier].
  /// Returns null if the input is null or empty.
  static VersionSpecifier? parse(String? specifier) {
    if (specifier == null || specifier.trim().isEmpty) {
      return null;
    }

    final constraints = specifier.split(RegExp(r'\s+')).map((part) {
      return VersionConstraint.parse(part);
    }).toList();

    return VersionSpecifier._(specifier, constraints);
  }

  /// Checks if the constraints of this specifier allow the given [version].
  bool allows(Version version) {
    return constraints.every((constraint) => constraint.allows(version));
  }

  @override
  String toString() => rawSpecifier;
}

/// Class representing a version with major, minor, and patch numbers.
class Version {
  final int major;
  final int minor;
  final int patch;

  Version(this.major, this.minor, this.patch);

  /// Parses a version string into a [Version].
  static Version parse(String versionString) {
    final versionParts = versionString.split('.');
    final major = int.parse(versionParts[0]);
    final minor = versionParts.length > 1 ? int.parse(versionParts[1]) : 0;
    final patch = versionParts.length > 2 ? int.parse(versionParts[2]) : 0;
    return Version(major, minor, patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Class representing a version constraint for matching versions.
class VersionConstraint {
  final String operator;
  final Version version;

  VersionConstraint._(this.operator, this.version);

  /// Parses a version constraint string, e.g., ">=7.1".
  static VersionConstraint parse(String constraint) {
    final match =
        RegExp(r'(>=|<=|>|<|=)?\s*(\d+\.\d+(?:\.\d+)?)').firstMatch(constraint);
    if (match == null) {
      throw ArgumentError('Invalid version constraint: $constraint');
    }

    final operator = match.group(1) ?? '=';

    final version = Version.parse(match.group(2)!);

    return VersionConstraint._(operator, version);
  }

  /// Checks if the given [version] is allowed by this constraint.
  bool allows(Version version) {
    switch (operator) {
      case '>=':
        return _compare(version) >= 0;
      case '<=':
        return _compare(version) <= 0;
      case '>':
        return _compare(version) > 0;
      case '<':
        return _compare(version) < 0;
      case '=':
      default:
        return _compare(version) == 0;
    }
  }

  int _compare(Version other) {
    if (version.major != other.major) {
      return other.major.compareTo(version.major);
    }
    if (version.minor != other.minor) {
      return other.minor.compareTo(version.minor);
    }
    return other.patch.compareTo(version.patch);
  }

  @override
  String toString() => '$operator ${version.toString()}';
}
