#!/usr/bin/env python3
"""Assemble bounded G4 records from final local reports and accepted G2 reviews.

This writes a candidate policy only. Review it and run router tests before promotion.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    # serde_json uses sorted keys and unpadded decimal exponents. Normalize float
    # tokens individually so text inside evidence descriptions is never changed.
    if isinstance(value, dict):
        return '{' + ','.join(canonical(k) + ':' + canonical(value[k]) for k in sorted(value)) + '}'
    if isinstance(value, list):
        return '[' + ','.join(canonical(item) for item in value) + ']'
    encoded = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    if isinstance(value, float):
        encoded = re.sub(r'e([+-])0+(\d+)$', r'e\1\2', encoded)
    return encoded


def digest(kind, value):
    payload = canonical(value).encode()
    return hashlib.sha256(b'lightcept-native-promotion-evidence-v1\0' + kind.encode() + b'\0' + payload).hexdigest()


def components(items):
    return [{('asset_sha256' if k == 'assetSha256' else k): v for k, v in item.items()} for item in items]


def build(directory):
    comparison = runpy.run_path(str(ROOT / 'scripts/compare-g4-integration.py'))['compare'](
        directory / 'macos-report.json', directory / 'linux-report.json', [directory / 'tiff-comparison.json'])
    if comparison['export_rgb16_max_channel_delta'] > 1:
        raise ValueError('G4 precision exceeds the accepted one-code bound')
    current = runpy.run_path(str(ROOT / 'scripts/build-cyna-linux-archive.py'))['pipeline_digest']()
    if comparison['pipeline_source_sha256'] != current:
        raise ValueError('reports do not qualify the current native sources')
    reports = json.loads((directory / 'macos-report.json').read_text())['sources']
    g2 = json.loads((directory / 'g2-report.json').read_text())
    if len(g2) != 2 or {s['source_sha256'] for s in g2} != {s['source_sha256'] for s in reports}:
        raise ValueError('G2 must contain both reviewed sources exactly once')
    precision = {
        'schema_version': 1, 'platforms': comparison['platforms'],
        'report_sha256': comparison['report_sha256'],
        'cyna_toolchain_lock_sha256': sha(ROOT / 'toolchains/cyna.lock'),
        'source_ids': [s['source'] for s in reports], 'measured_outputs': {},
        'measured_preview_rgb8_max_channel_delta': comparison['preview_rgb8_max_channel_delta'],
        'measured_export_rgb16_max_channel_delta': comparison['export_rgb16_max_channel_delta'],
        'scope': 'Local macOS/Linux ARM64; pinned as-shot sources; 1200x800 previews at -2/0/+2 EV and 6000x4000 TIFF16 at 0 EV. Not a universal error bound.',
        'decoded_tiff_comparison_sha256': comparison['decoded_tiff_comparison_sha256'],
    }
    for source in reports:
        contract = source['contract']
        parts = components(contract['components'])
        assets = {p['stage']: p.get('asset_sha256') for p in parts}
        precision['measured_outputs'][source['source']] = {
            'source_sha256': source['source_sha256'], 'storage_variant': contract['sourceVariant'],
            'embedded_profile_sha256': assets['profile'], 'pipeline_source_sha256': current,
            'output_icc_sha256': assets['output'], 'render_components': parts,
            'previews': [{'exposure_ev': p['exposure_ev'], 'dimensions': [1200, 800], 'sha256': p['rgba8_sha256']} for p in source['previews']],
            'export': {'exposure_ev': 0.0, 'dimensions': [6000, 4000], 'sha256': source['tiff_sha256']},
        }
    precision_hash = digest('precision', precision)
    promotions = []
    for source in reports:
        prior = ROOT / 'qualification/evidence/g4-candidate-integration-2026-10-21' / ('quality-' + source['source'].removesuffix('.DNG') + '.json')
        quality = json.loads(prior.read_text())
        scene = quality['reference_scenes'][0]
        measured = next(s for s in g2 if s['source_sha256'] == source['source_sha256'])
        if measured['pipeline_source_sha256'] != current or measured['max_camera_difference'] > 1e-4:
            raise ValueError('G2 final-build identity or camera error failed')
        if [r['ev'] for r in measured['renders']] != [-2.0, 0.0, 2.0]:
            raise ValueError('G2 exposure sweep incomplete')
        for reviewed, render in zip(scene['exposures'], measured['renders']):
            if (reviewed['native_sha256'] != render['native_sha256'] or reviewed['reference_sha256'] != render['reference_sha256']
                    or render['max_rgb8_difference'] > 1 or not render['candidate_staged_exact']):
                raise ValueError('final images differ from accepted G2 scene review')
        parts = components(source['contract']['components'])
        scene.update(pipeline_source_sha256=current, render_components=parts, report_sha256=sha(directory / 'g2-report.json'))
        quality['synthetic_report_sha256'] = sha(directory / 'native-tests.log')
        record = {
            'storage_variant': scene['storage_variant'], 'profile_sha256': scene['profile_sha256'],
            'pipeline_source_sha256': current, 'output_icc_sha256': scene['output_icc_sha256'],
            'required_stages': [p['stage'] for p in parts], 'precision_class': 'scalar-cpu',
            'precision_bound': {'executionScope': 'cross-platform-pinned-outputs-v1',
                                'previewRgb8MaxChannelDelta': 0,
                                'exportRgb16MaxChannelDelta': comparison['export_rgb16_max_channel_delta'],
                                'evidenceSha256': precision_hash},
            'precision_evidence': precision, 'precision_evidence_sha256': precision_hash,
            'quality_evidence': quality, 'quality_evidence_sha256': digest('quality', quality),
        }
        promotions.append(record)
    (directory / 'precision-comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')
    return {'schema_version': 1, 'promotions': promotions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence_directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(build(args.evidence_directory), indent=2) + '\n')


if __name__ == '__main__':
    main()
