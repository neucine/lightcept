#!/usr/bin/env python3
"""Compare G4 product integration receipts from macOS and Linux.

This records local evidence; it does not publish a production promotion.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def compare(first, second, tiff_comparisons=()):
    reports = [json.loads(path.read_text()) for path in (first, second)]
    platforms = [(r['platform'], r['architecture']) for r in reports]
    if platforms[0] == platforms[1]:
        raise ValueError('expected distinct platform identities')
    expected_sources = {
        '05513ee72f7cac4165534c9f64995412084f414a033c80c473c79fd94154292e',
        '1e318af31be4baa9949f0ed4af5cfe8ffb2c180e2c12926cd75ac1d029bb0fae',
    }
    for report in reports:
        if len(report['sources']) != 2 or {s['source_sha256'] for s in report['sources']} != expected_sources:
            raise ValueError('expected both pinned Ricoh sources exactly once')
        for source in report['sources']:
            contract = source['contract']
            if contract['source']['sha256'] != source['source_sha256'] or contract.get('precisionBound') is not None:
                raise ValueError('invalid candidate source or precision claim')
            pipeline = next(c for c in contract['components'] if c['stage'] == 'pipeline-source')
            if pipeline['assetSha256'] != report['pipeline_source_sha256']:
                raise ValueError('pipeline identity mismatch')
            if [p['exposure_ev'] for p in source['previews']] != [-2.0, 0.0, 2.0]:
                raise ValueError('incomplete exposure sweep')
            hashes = [report['pipeline_source_sha256'], source['tiff_sha256'], source['jpeg_sha256']]
            hashes.extend(p['rgba8_sha256'] for p in source['previews'])
            if any(not isinstance(h, str) or not re.fullmatch('[0-9a-f]{64}', h) for h in hashes):
                raise ValueError('invalid output digest')
    if reports[0]['pipeline_source_sha256'] != reports[1]['pipeline_source_sha256']:
        raise ValueError('different pipeline builds')
    tiff_delta = 0
    used_comparisons = []
    for a, b in zip(*(sorted(r['sources'], key=lambda s: s['source']) for r in reports)):
        if {k:v for k,v in a.items() if k != 'tiff_sha256'} != {k:v for k,v in b.items() if k != 'tiff_sha256'}:
            raise ValueError('preview, JPEG or contract mismatch')
        if a['tiff_sha256'] != b['tiff_sha256']:
            match = None
            for path in tiff_comparisons:
                decoded = json.loads(path.read_text())
                if decoded.get('tiff_sha256') == [a['tiff_sha256'], b['tiff_sha256']]:
                    match = decoded
                    used_comparisons.append(hashlib.sha256(path.read_bytes()).hexdigest())
                    break
            if match is None:
                raise ValueError('TIFF mismatch: provide a hash-bound decoded comparison')
            icc = next(c['assetSha256'] for c in a['contract']['components'] if c['stage'] == 'output')
            maximum = match.get('max_rgb16_channel_delta')
            count = match.get('different_channels')
            if (match.get('dimensions') != [6000,4000] or match.get('compared_channels') != 72000000
                    or match.get('icc_sha256') != icc or type(maximum) is not int or not 0 <= maximum <= 65535
                    or type(count) is not int or not 0 <= count <= 72000000 or (maximum == 0) != (count == 0)):
                raise ValueError('invalid decoded TIFF measurement')
            tiff_delta = max(tiff_delta, maximum)
    return {
        'schema_version': 1, 'scope': 'local-g4-product-integration-v1',
        'pipeline_source_sha256': reports[0]['pipeline_source_sha256'],
        'platforms': platforms,
        'report_sha256': [hashlib.sha256(p.read_bytes()).hexdigest() for p in (first, second)],
        'preview_count': 6, 'tiff_count': 2, 'jpeg_count': 2,
        'preview_rgb8_max_channel_delta': 0, 'export_rgb16_max_channel_delta': tiff_delta,
        'jpeg_files_identical': True,
        'decoded_tiff_comparison_sha256': used_comparisons,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('first', type=Path)
    parser.add_argument('second', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tiff-comparison', type=Path, action='append', default=[])
    parser.add_argument('--max-rgb16-delta', type=int, default=1, help='accepted corpus bound; fail rather than expand it')
    args = parser.parse_args()
    result = compare(args.first, args.second, args.tiff_comparison)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    if not 0 <= args.max_rgb16_delta <= 1 or result['export_rgb16_max_channel_delta'] > args.max_rgb16_delta:
        raise ValueError('measured TIFF difference exceeds the accepted G4 bound')


if __name__ == '__main__':
    main()
