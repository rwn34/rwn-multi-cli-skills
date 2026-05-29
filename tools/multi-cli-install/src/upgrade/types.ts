export type FileClassification =
  | 'framework-owned'
  | 'adopter-customized-expected'
  | 'adopter-may-extend';

export interface UpgradeHistoryEntry {
  from: string;
  to: string;
  at: string;
}

export interface FrameworkVersion {
  framework_version: string;
  installer_name: string;
  installer_version: string;
  installed_at: string;
  upgrade_history: UpgradeHistoryEntry[];
}

export interface ManifestEntry {
  sha256: string;
  version_first_seen: string;
  classification: FileClassification;
}

export interface FrameworkManifest {
  version: string;
  files: Record<string, ManifestEntry>;
}
