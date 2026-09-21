// VPatch-compatible reader for the Linux installer.
//
// This is an independent Rust implementation of the documented VPatch file
// layout. VPatch's original zlib-style notice is distributed with the
// installer in licenses/VPatch-zlib.txt.

use anyhow::{bail, Context, Result};
use crc32fast::hash as crc32;
use std::{
    fs,
    io::{Cursor, Read, Seek, SeekFrom},
    path::Path,
};

const VPAT_MAGIC: u32 = 0x5441_5056;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PatchOutcome {
    Applied,
    AlreadyPatched,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Checksum {
    Crc32(u32),
    Md5([u8; 16]),
}

pub fn apply_file(
    patch_path: &Path,
    source_path: &Path,
    output_path: &Path,
) -> Result<PatchOutcome> {
    let patch = fs::read(patch_path)
        .with_context(|| format!("패치 파일을 읽을 수 없습니다: {}", patch_path.display()))?;
    let source = fs::read(source_path)
        .with_context(|| format!("원본 파일을 읽을 수 없습니다: {}", source_path.display()))?;
    let (outcome, output) = apply_bytes(&patch, &source)?;
    if let Some(output) = output {
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(output_path, output)
            .with_context(|| format!("임시 결과를 쓸 수 없습니다: {}", output_path.display()))?;
    }
    Ok(outcome)
}

fn apply_bytes(patch: &[u8], source: &[u8]) -> Result<(PatchOutcome, Option<Vec<u8>>)> {
    if patch.len() < 8 {
        bail!("VPatch 파일이 너무 짧습니다");
    }

    let mut cursor = Cursor::new(patch);
    let first = read_u32(&mut cursor)?;
    if first != VPAT_MAGIC {
        let offset = u32::from_le_bytes(patch[patch.len() - 4..].try_into().unwrap()) as u64;
        if offset + 8 > patch.len() as u64 {
            bail!("VPatch 헤더 위치가 올바르지 않습니다");
        }
        cursor.seek(SeekFrom::Start(offset))?;
        if read_u32(&mut cursor)? != VPAT_MAGIC {
            bail!("VPatch 헤더를 찾을 수 없습니다");
        }
    }

    let raw_count = read_u32(&mut cursor)?;
    let md5_mode = raw_count & 0x8000_0000 != 0;
    let patch_count = raw_count & 0x00ff_ffff;
    let source_checksum = checksum(source, md5_mode);
    let mut already_patched = false;

    for _ in 0..patch_count {
        let block_count = read_i32(&mut cursor)?;
        if block_count < 0 {
            bail!("VPatch 블록 수가 올바르지 않습니다");
        }
        let expected_source = read_checksum(&mut cursor, md5_mode)?;
        let expected_output = read_checksum(&mut cursor, md5_mode)?;
        let patch_size = read_i32(&mut cursor)?;
        if patch_size < 0 {
            bail!("VPatch 데이터 크기가 올바르지 않습니다");
        }

        if source_checksum == expected_output {
            already_patched = true;
        }

        if source_checksum != expected_source {
            let next = cursor
                .position()
                .checked_add(patch_size as u64)
                .context("VPatch 위치 계산이 넘쳤습니다")?;
            if next > patch.len() as u64 {
                bail!("VPatch 데이터가 잘렸습니다");
            }
            cursor.seek(SeekFrom::Start(next))?;
            continue;
        }

        let mut output = Vec::new();
        for _ in 0..block_count {
            let block_type = read_u8(&mut cursor)?;
            match block_type {
                1..=3 => {
                    let len = read_block_size(&mut cursor, block_type)?;
                    let offset = read_u32(&mut cursor)? as usize;
                    let end = offset
                        .checked_add(len)
                        .context("원본 블록 범위가 넘쳤습니다")?;
                    let bytes = source
                        .get(offset..end)
                        .context("VPatch가 원본 파일 범위를 벗어났습니다")?;
                    output.extend_from_slice(bytes);
                }
                5..=7 => {
                    let len = read_block_size(&mut cursor, block_type - 4)?;
                    let start = cursor.position() as usize;
                    let end = start
                        .checked_add(len)
                        .context("리터럴 블록 범위가 넘쳤습니다")?;
                    let bytes = patch
                        .get(start..end)
                        .context("VPatch 리터럴 데이터가 잘렸습니다")?;
                    output.extend_from_slice(bytes);
                    cursor.seek(SeekFrom::Start(end as u64))?;
                }
                255 => {
                    let next = cursor
                        .position()
                        .checked_add(8)
                        .context("시간 블록 범위가 넘쳤습니다")?;
                    if next > patch.len() as u64 {
                        bail!("VPatch 시간 데이터가 잘렸습니다");
                    }
                    cursor.seek(SeekFrom::Start(next))?;
                }
                _ => bail!("지원하지 않는 VPatch 블록 형식입니다: {block_type}"),
            }
        }

        if checksum(&output, md5_mode) != expected_output {
            bail!("VPatch 결과 체크섬이 일치하지 않습니다");
        }
        return Ok((PatchOutcome::Applied, Some(output)));
    }

    if already_patched {
        Ok((PatchOutcome::AlreadyPatched, None))
    } else {
        bail!("이 원본 파일과 일치하는 VPatch 항목이 없습니다")
    }
}

fn checksum(data: &[u8], md5_mode: bool) -> Checksum {
    if md5_mode {
        Checksum::Md5(md5::compute(data).0)
    } else {
        Checksum::Crc32(crc32(data))
    }
}

fn read_checksum(cursor: &mut Cursor<&[u8]>, md5_mode: bool) -> Result<Checksum> {
    if md5_mode {
        let mut value = [0u8; 16];
        cursor
            .read_exact(&mut value)
            .context("VPatch MD5 데이터가 잘렸습니다")?;
        Ok(Checksum::Md5(value))
    } else {
        Ok(Checksum::Crc32(read_u32(cursor)?))
    }
}

fn read_block_size(cursor: &mut Cursor<&[u8]>, width: u8) -> Result<usize> {
    let value = match width {
        1 => read_u8(cursor)? as usize,
        2 => read_u16(cursor)? as usize,
        3 => read_u32(cursor)? as usize,
        _ => unreachable!(),
    };
    if value == 0 {
        bail!("VPatch에 길이가 0인 블록이 있습니다");
    }
    Ok(value)
}

fn read_u8(cursor: &mut Cursor<&[u8]>) -> Result<u8> {
    let mut value = [0u8; 1];
    cursor
        .read_exact(&mut value)
        .context("VPatch 데이터가 잘렸습니다")?;
    Ok(value[0])
}

fn read_u16(cursor: &mut Cursor<&[u8]>) -> Result<u16> {
    let mut value = [0u8; 2];
    cursor
        .read_exact(&mut value)
        .context("VPatch 데이터가 잘렸습니다")?;
    Ok(u16::from_le_bytes(value))
}

fn read_u32(cursor: &mut Cursor<&[u8]>) -> Result<u32> {
    let mut value = [0u8; 4];
    cursor
        .read_exact(&mut value)
        .context("VPatch 데이터가 잘렸습니다")?;
    Ok(u32::from_le_bytes(value))
}

fn read_i32(cursor: &mut Cursor<&[u8]>) -> Result<i32> {
    Ok(read_u32(cursor)? as i32)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn md5_patch(source: &[u8], output: &[u8], blocks: &[u8], block_count: u32) -> Vec<u8> {
        let mut patch = Vec::new();
        patch.extend_from_slice(&VPAT_MAGIC.to_le_bytes());
        patch.extend_from_slice(&0x8000_0001u32.to_le_bytes());
        patch.extend_from_slice(&block_count.to_le_bytes());
        patch.extend_from_slice(&md5::compute(source).0);
        patch.extend_from_slice(&md5::compute(output).0);
        patch.extend_from_slice(&(blocks.len() as u32).to_le_bytes());
        patch.extend_from_slice(blocks);
        patch
    }

    #[test]
    fn applies_copy_and_literal_blocks() {
        let source = b"ABCDE";
        let output = b"BCxyz";
        let mut blocks = Vec::new();
        blocks.extend_from_slice(&[1, 2]);
        blocks.extend_from_slice(&1u32.to_le_bytes());
        blocks.extend_from_slice(&[5, 3]);
        blocks.extend_from_slice(b"xyz");
        let patch = md5_patch(source, output, &blocks, 2);
        let result = apply_bytes(&patch, source).unwrap();
        assert_eq!(result.0, PatchOutcome::Applied);
        assert_eq!(result.1.unwrap(), output);
    }

    #[test]
    fn recognizes_already_patched_input() {
        let source = b"original";
        let output = b"patched";
        let blocks = [5, output.len() as u8]
            .into_iter()
            .chain(output.iter().copied())
            .collect::<Vec<_>>();
        let patch = md5_patch(source, output, &blocks, 1);
        let result = apply_bytes(&patch, output).unwrap();
        assert_eq!(result, (PatchOutcome::AlreadyPatched, None));
    }
}
