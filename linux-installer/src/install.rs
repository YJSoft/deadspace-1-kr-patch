use crate::vpatch::{self, PatchOutcome};
use anyhow::{bail, ensure, Context, Result};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    env, fs,
    io::Read,
    path::{Path, PathBuf},
    process,
    time::{SystemTime, UNIX_EPOCH},
};

pub const VERSION: &str = "0.3";
pub const LAUNCH_OPTION: &str = r#"WINEDLLOVERRIDES="xinput1_3=n,b" %command%"#;

const FONT_REL: &str = "text_assets/text_assets_global.str";
const STEAM_TEXT_REL: &str = "text_assets/text/12F4D5F8.str";
const PATCH_TEXT_REL: &str = "text_assets/text/D8CBB618.str";
const RUNTIME_FILES: [&str; 4] = [
    "ds1k_utf8.dll",
    "xinput1_3.dll",
    "SDL3.dll",
    "DeadSpaceFixes.ini",
];

#[derive(Debug, Deserialize)]
struct Manifest {
    patch: ManifestPatch,
    inputs: Vec<ManifestFile>,
    outputs: Vec<ManifestFile>,
}

#[derive(Debug, Deserialize)]
struct ManifestPatch {
    file: String,
    sha256: String,
}

#[derive(Debug, Deserialize)]
struct ManifestFile {
    file: String,
    sha256: String,
}

#[derive(Clone, Debug)]
pub struct Resources {
    pub root: PathBuf,
}

impl Resources {
    pub fn discover() -> Result<Self> {
        if let Some(path) = env::var_os("DS1K_RESOURCE_DIR") {
            return Self::from_root(PathBuf::from(path));
        }

        let exe = env::current_exe().context("실행 파일 위치를 확인할 수 없습니다")?;
        if let Some(usr) = exe.parent().and_then(Path::parent) {
            let bundled = usr.join("share/deadspace1-kr");
            if bundled.is_dir() {
                return Self::from_root(bundled);
            }
        }

        let repo = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .context("개발용 저장소 경로를 확인할 수 없습니다")?;
        Self::from_root(repo.join("linux-installer/dev-resources"))
    }

    pub fn from_root(root: PathBuf) -> Result<Self> {
        let required = [
            "patches/manifest.json",
            "patches/deadspace1-kr-v0.3.pat",
            "runtime/ds1k_utf8.dll",
            "runtime/xinput1_3.dll",
            "runtime/SDL3.dll",
            "runtime/DeadSpaceFixes.ini",
        ];
        for relative in required {
            ensure!(
                root.join(relative).is_file(),
                "설치기 구성 파일이 없습니다: {}",
                root.join(relative).display()
            );
        }
        Ok(Self { root })
    }

    fn manifest(&self) -> Result<Manifest> {
        let path = self.root.join("patches/manifest.json");
        let data = fs::read(&path)?;
        serde_json::from_slice(&data)
            .with_context(|| format!("매니페스트 형식이 잘못되었습니다: {}", path.display()))
    }

    pub fn verify(&self) -> Result<()> {
        let manifest = self.manifest()?;
        let patch = self.root.join("patches").join(&manifest.patch.file);
        ensure_hash(&patch, &manifest.patch.sha256, "배포 패치")
    }
}

#[derive(Debug)]
struct PreparedSources {
    backup_dir: PathBuf,
    legacy_backup: Option<PathBuf>,
    font: PathBuf,
    text: PathBuf,
    text_original_absent: bool,
    upgrade: bool,
    backup_complete: bool,
}

pub fn is_game_dir(path: &Path) -> bool {
    path.join("Dead Space.exe").is_file()
        && path.join(FONT_REL).is_file()
        && (path.join(STEAM_TEXT_REL).is_file() || path.join(PATCH_TEXT_REL).is_file())
}

pub fn detect_game_dirs() -> Vec<PathBuf> {
    let mut roots = BTreeSet::new();
    if let Some(home) = env::var_os("HOME").map(PathBuf::from) {
        roots.insert(home.join(".local/share/Steam"));
        roots.insert(home.join(".steam/steam"));
        roots.insert(home.join(".steam/root"));
        roots.insert(home.join(".var/app/com.valvesoftware.Steam/data/Steam"));
    }
    if let Some(data) = env::var_os("XDG_DATA_HOME").map(PathBuf::from) {
        roots.insert(data.join("Steam"));
    }

    let mut libraries = roots.clone();
    for root in roots {
        let vdf = root.join("steamapps/libraryfolders.vdf");
        if let Ok(text) = fs::read_to_string(vdf) {
            for path in steam_library_paths(&text) {
                libraries.insert(path);
            }
        }
    }

    let mut found = Vec::new();
    let mut seen = BTreeSet::new();
    for library in libraries {
        let candidate = library.join("steamapps/common/Dead Space");
        if is_game_dir(&candidate) {
            let canonical = candidate.canonicalize().unwrap_or(candidate);
            if seen.insert(canonical.clone()) {
                found.push(canonical);
            }
        }
    }
    found
}

pub fn install<F>(game: &Path, resources: &Resources, mut progress: F) -> Result<()>
where
    F: FnMut(&str),
{
    ensure!(is_game_dir(game), "Dead Space (2008) 설치 폴더가 아닙니다");
    let manifest = resources.manifest()?;
    let patch_path = resources.root.join("patches").join(&manifest.patch.file);
    ensure_hash(&patch_path, &manifest.patch.sha256, "배포 패치")?;
    for file in &RUNTIME_FILES {
        ensure!(
            resources.root.join("runtime").join(file).is_file(),
            "런타임 파일이 없습니다: {file}"
        );
    }

    progress("게임 파일과 기존 설치 정보를 확인하는 중...");
    let mut prepared = prepare_sources(game, &manifest)?;
    let temp = TempDir::new()?;
    let patched_font = temp.path.join("text_assets_global.str");
    let patched_text = temp.path.join("D8CBB618.str");

    progress("원본 파일에서 한국어 리소스를 생성하는 중...");
    ensure_applied(vpatch::apply_file(
        &patch_path,
        &prepared.font,
        &patched_font,
    )?)?;
    ensure_applied(vpatch::apply_file(
        &patch_path,
        &prepared.text,
        &patched_text,
    )?)?;
    ensure_output_hash(&patched_font, FONT_REL, &manifest)?;
    ensure_output_hash(&patched_text, PATCH_TEXT_REL, &manifest)?;

    if let Some(old) = prepared.legacy_backup.take() {
        progress("기존 백업 폴더 이름을 새 형식으로 변경하는 중...");
        if prepared.backup_dir.exists() {
            let empty = prepared
                .backup_dir
                .read_dir()
                .map(|mut entries| entries.next().is_none())
                .unwrap_or(false);
            ensure!(
                empty,
                "DS1K_Backup 폴더가 비어 있지 않아 이전 백업을 옮길 수 없습니다"
            );
            fs::remove_dir(&prepared.backup_dir)?;
        }
        fs::rename(&old, &prepared.backup_dir)
            .with_context(|| format!("백업 폴더 이름을 변경할 수 없습니다: {}", old.display()))?;
    }

    progress("원본 파일을 안전하게 백업하는 중...");
    if !prepared.upgrade {
        create_backup(
            game,
            &prepared.backup_dir,
            prepared.text_original_absent,
            false,
        )?;
        prepared.backup_complete = true;
    } else if !prepared.backup_complete {
        create_backup(
            game,
            &prepared.backup_dir,
            prepared.text_original_absent,
            true,
        )?;
        prepared.backup_complete = true;
    }
    ensure!(prepared.backup_complete, "원본 백업을 준비하지 못했습니다");

    let saved_config = if prepared.upgrade {
        fs::read(game.join("DeadSpaceFixes.ini")).ok()
    } else {
        None
    };

    let mutation = (|| -> Result<()> {
        if prepared.upgrade && backup_is_complete(&prepared.backup_dir) {
            progress("기존 패치를 원본 상태로 복원하는 중...");
            restore_backup(game, &prepared.backup_dir)?;
            if let Some(config) = &saved_config {
                fs::write(game.join("DeadSpaceFixes.ini"), config)?;
            }
        }

        progress("한국어 리소스와 실행 파일을 설치하는 중...");
        replace_file(&patched_font, &game.join(FONT_REL))?;
        replace_file(&patched_text, &game.join(PATCH_TEXT_REL))?;
        for file in ["ds1k_utf8.dll", "xinput1_3.dll", "SDL3.dll"] {
            replace_file(&resources.root.join("runtime").join(file), &game.join(file))?;
        }
        let config = game.join("DeadSpaceFixes.ini");
        if !config.exists() {
            replace_file(&resources.root.join("runtime/DeadSpaceFixes.ini"), &config)?;
        }

        install_metadata(game, resources)?;
        Ok(())
    })();

    if let Err(error) = mutation {
        progress("설치 중 오류가 발생해 원본 파일을 복원하는 중...");
        let rollback = restore_backup(game, &prepared.backup_dir);
        let _ = fs::remove_dir_all(game.join("DS1K_Patch"));
        if let Err(rollback_error) = rollback {
            bail!("{error:#}\n\n원본 복원도 실패했습니다: {rollback_error:#}");
        }
        return Err(error);
    }

    progress("설치가 완료되었습니다. 아래 Steam 실행 옵션을 복사해 적용하십시오.");
    Ok(())
}

pub fn uninstall<F>(game: &Path, mut progress: F) -> Result<()>
where
    F: FnMut(&str),
{
    ensure!(is_game_dir(game), "Dead Space (2008) 설치 폴더가 아닙니다");
    let backup = game.join("DS1K_Backup");
    ensure!(
        backup_is_complete(&backup),
        "완전한 원본 백업을 찾을 수 없습니다: {}",
        backup.display()
    );
    progress("백업에서 원본 게임 파일을 복원하는 중...");
    restore_backup(game, &backup)?;
    let patch_dir = game.join("DS1K_Patch");
    if patch_dir.exists() {
        fs::remove_dir_all(&patch_dir).with_context(|| {
            format!("설치 정보 폴더를 지울 수 없습니다: {}", patch_dir.display())
        })?;
    }
    progress("패치를 제거했습니다. 원본 백업 폴더는 안전을 위해 유지했습니다.");
    Ok(())
}

fn prepare_sources(game: &Path, manifest: &Manifest) -> Result<PreparedSources> {
    let target_backup = game.join("DS1K_Backup");
    let legacy_backup = if target_backup.join(FONT_REL).is_file() {
        None
    } else {
        find_legacy_backup(game)
    };
    let active_backup = legacy_backup.as_deref().unwrap_or(&target_backup);
    let upgrade = active_backup.join(FONT_REL).is_file()
        || game.join("DS1K_Patch/installed-version.txt").is_file();
    let complete = backup_is_complete(active_backup);

    if upgrade && complete {
        let font = active_backup.join(FONT_REL);
        let (text, absent) = if active_backup.join(PATCH_TEXT_REL).is_file() {
            (active_backup.join(PATCH_TEXT_REL), false)
        } else {
            (game.join(STEAM_TEXT_REL), true)
        };
        if input_is_supported(&font, FONT_REL, manifest)
            && input_is_supported(
                &text,
                if absent {
                    STEAM_TEXT_REL
                } else {
                    PATCH_TEXT_REL
                },
                manifest,
            )
        {
            return Ok(PreparedSources {
                backup_dir: target_backup,
                legacy_backup,
                font,
                text,
                text_original_absent: absent,
                upgrade,
                backup_complete: true,
            });
        }
    }

    let font = game.join(FONT_REL);
    ensure!(
        input_is_supported(&font, FONT_REL, manifest),
        "지원되는 원본 글꼴 리소스가 아닙니다. Steam에서 게임 파일을 복구한 뒤 다시 시도하십시오"
    );
    let steam_text = game.join(STEAM_TEXT_REL);
    let ea_text = game.join(PATCH_TEXT_REL);
    let (text, absent) = if input_is_supported(&steam_text, STEAM_TEXT_REL, manifest) {
        (steam_text, true)
    } else if input_is_supported(&ea_text, PATCH_TEXT_REL, manifest) {
        (ea_text, false)
    } else {
        bail!("지원되는 원본 번역 리소스가 아닙니다. Steam에서 게임 파일을 복구한 뒤 다시 시도하십시오");
    };

    Ok(PreparedSources {
        backup_dir: target_backup,
        legacy_backup,
        font,
        text,
        text_original_absent: absent,
        upgrade,
        backup_complete: false,
    })
}

fn create_backup(game: &Path, backup: &Path, text_absent: bool, recovery: bool) -> Result<()> {
    fs::create_dir_all(backup.join("text_assets/text"))?;
    fs::create_dir_all(backup.join("runtime"))?;
    replace_file(&game.join(FONT_REL), &backup.join(FONT_REL))?;

    let saved_text = backup.join(PATCH_TEXT_REL);
    let absent_marker = backup.join(format!("{PATCH_TEXT_REL}.absent"));
    remove_if_exists(&saved_text)?;
    remove_if_exists(&absent_marker)?;
    if text_absent {
        fs::write(absent_marker, b"absent\n")?;
    } else {
        replace_file(&game.join(PATCH_TEXT_REL), &saved_text)?;
    }

    for file in RUNTIME_FILES {
        let saved = backup.join("runtime").join(file);
        let absent = backup.join("runtime").join(format!("{file}.absent"));
        if saved.exists() || absent.exists() {
            continue;
        }
        if recovery {
            fs::write(absent, b"absent\n")?;
        } else if game.join(file).is_file() {
            replace_file(&game.join(file), &saved)?;
        } else {
            fs::write(absent, b"absent\n")?;
        }
    }
    Ok(())
}

fn restore_backup(game: &Path, backup: &Path) -> Result<()> {
    ensure!(
        backup_is_complete(backup),
        "원본 백업이 없거나 불완전합니다: {}",
        backup.display()
    );
    replace_file(&backup.join(FONT_REL), &game.join(FONT_REL))?;
    let saved_text = backup.join(PATCH_TEXT_REL);
    if saved_text.is_file() {
        replace_file(&saved_text, &game.join(PATCH_TEXT_REL))?;
    } else {
        remove_if_exists(&game.join(PATCH_TEXT_REL))?;
    }
    for file in RUNTIME_FILES {
        let saved = backup.join("runtime").join(file);
        if saved.is_file() {
            replace_file(&saved, &game.join(file))?;
        } else {
            remove_if_exists(&game.join(file))?;
        }
    }
    Ok(())
}

fn backup_is_complete(backup: &Path) -> bool {
    if !backup.join(FONT_REL).is_file() {
        return false;
    }
    if !backup.join(PATCH_TEXT_REL).is_file()
        && !backup.join(format!("{PATCH_TEXT_REL}.absent")).is_file()
    {
        return false;
    }
    RUNTIME_FILES.iter().all(|file| {
        backup.join("runtime").join(file).is_file()
            || backup
                .join("runtime")
                .join(format!("{file}.absent"))
                .is_file()
    })
}

fn install_metadata(game: &Path, resources: &Resources) -> Result<()> {
    let destination = game.join("DS1K_Patch");
    fs::create_dir_all(&destination)?;
    if resources.root.join("docs").is_dir() {
        copy_tree(&resources.root.join("docs"), &destination)?;
    }
    if resources.root.join("licenses").is_dir() {
        copy_tree(
            &resources.root.join("licenses"),
            &destination.join("licenses"),
        )?;
    }
    replace_file(
        &resources.root.join("patches/manifest.json"),
        &destination.join("manifest.json"),
    )?;
    let commit = option_env!("DS1K_GIT_HASH").unwrap_or("dev");
    fs::write(
        destination.join("installed-version.txt"),
        format!("Dead Space 1 KR {VERSION}\nCommit {commit}\nInstaller Linux AppImage\n"),
    )?;
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let target = destination.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_tree(&entry.path(), &target)?;
        } else {
            replace_file(&entry.path(), &target)?;
        }
    }
    Ok(())
}

fn replace_file(source: &Path, destination: &Path) -> Result<()> {
    let parent = destination
        .parent()
        .context("대상 파일의 상위 폴더가 없습니다")?;
    fs::create_dir_all(parent)?;
    let name = destination
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");
    let temporary = parent.join(format!(".{name}.ds1k-new-{}", process::id()));
    remove_if_exists(&temporary)?;
    fs::copy(source, &temporary).with_context(|| {
        format!(
            "파일을 복사할 수 없습니다: {} -> {}",
            source.display(),
            destination.display()
        )
    })?;
    remove_if_exists(destination)?;
    fs::rename(&temporary, destination)
        .with_context(|| format!("새 파일을 적용할 수 없습니다: {}", destination.display()))?;
    Ok(())
}

fn remove_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => {
            Err(error).with_context(|| format!("파일을 지울 수 없습니다: {}", path.display()))
        }
    }
}

fn input_is_supported(path: &Path, relative: &str, manifest: &Manifest) -> bool {
    let Ok(hash) = sha256_file(path) else {
        return false;
    };
    manifest
        .inputs
        .iter()
        .any(|item| item.file == relative && item.sha256.eq_ignore_ascii_case(&hash))
}

fn ensure_output_hash(path: &Path, relative: &str, manifest: &Manifest) -> Result<()> {
    let expected = manifest
        .outputs
        .iter()
        .find(|item| item.file == relative)
        .with_context(|| format!("결과 해시가 매니페스트에 없습니다: {relative}"))?;
    ensure_hash(path, &expected.sha256, "생성 결과")
}

fn ensure_hash(path: &Path, expected: &str, label: &str) -> Result<()> {
    let actual = sha256_file(path)?;
    ensure!(
        actual.eq_ignore_ascii_case(expected),
        "{label} 무결성 검사가 실패했습니다: {}",
        path.display()
    );
    Ok(())
}

fn sha256_file(path: &Path) -> Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:X}", hasher.finalize()))
}

fn ensure_applied(outcome: PatchOutcome) -> Result<()> {
    ensure!(
        outcome == PatchOutcome::Applied,
        "이미 수정된 리소스는 원본 백업으로 사용할 수 없습니다"
    );
    Ok(())
}

fn find_legacy_backup(game: &Path) -> Option<PathBuf> {
    let mut candidates = fs::read_dir(game)
        .ok()?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_dir()
                && path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with("DS1K_Backup_v"))
                && path.join(FONT_REL).is_file()
        })
        .collect::<Vec<_>>();
    candidates.sort();
    candidates.into_iter().next()
}

fn steam_library_paths(text: &str) -> Vec<PathBuf> {
    text.lines()
        .filter_map(|line| {
            let tokens = quoted_tokens(line);
            (tokens.len() >= 2 && tokens[0] == "path")
                .then(|| PathBuf::from(tokens[1].replace("\\\\", "\\")))
        })
        .collect()
}

fn quoted_tokens(line: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    let mut escaped = false;
    for ch in line.chars() {
        if !quoted {
            if ch == '"' {
                quoted = true;
                current.clear();
            }
            continue;
        }
        if escaped {
            current.push(ch);
            escaped = false;
        } else if ch == '\\' {
            current.push(ch);
            escaped = true;
        } else if ch == '"' {
            quoted = false;
            result.push(current.clone());
        } else {
            current.push(ch);
        }
    }
    result
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new() -> Result<Self> {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let path = env::temp_dir().join(format!("deadspace1-kr-{}-{stamp}", process::id()));
        fs::create_dir_all(&path)?;
        Ok(Self { path })
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_modern_steam_library_vdf() {
        let vdf = r#"
            "0"
            {
                "path" "/home/test/.local/share/Steam"
            }
            "1"
            {
                "path" "/mnt/games/SteamLibrary"
            }
        "#;
        assert_eq!(
            steam_library_paths(vdf),
            vec![
                PathBuf::from("/home/test/.local/share/Steam"),
                PathBuf::from("/mnt/games/SteamLibrary")
            ]
        );
    }

    #[test]
    fn parses_escaped_windows_library_for_compatibility() {
        let vdf = r#""path" "P:\\SteamLibrary""#;
        assert_eq!(
            steam_library_paths(vdf),
            vec![PathBuf::from(r"P:\SteamLibrary")]
        );
    }
}
