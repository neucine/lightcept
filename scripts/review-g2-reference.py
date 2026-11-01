#!/usr/bin/env python3
"""Package fixed G2 scene regions; no region selection from difference images."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'target/g2-reference'
REVIEW = BASE / 'review'
EVIDENCE = ROOT / 'qualification/evidence/g2-reference-parity-2026-10-21'

def run(args):
    subprocess.run(['magick', *map(str, args)], check=True, capture_output=True)

def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        return digest.hexdigest()

def artifact(path):
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path)}

def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    originals = json.loads((ROOT / 'qualification/evidence/g3-output-fidelity-2026-10-21/outputs.json').read_text())
    manifest = json.loads((ROOT / 'qualification/native-sources.json').read_text())['sources']
    reports = json.loads((BASE / 'report.json').read_text())
    for report in reports:
        source = next(s for s in manifest if s['file'] == report['source'])
        assert report['source_sha256'] == source['sha256']
        for actual, expected in [('crop','expected_crop'), ('cfa','expected_cfa'), ('black','expected_black_levels'), ('white','expected_white_level')]:
            assert report['geometry'][actual] == source[expected], (actual, report['source'])
        assert report['geometry']['stored'] == [6112,4064]
        assert report['geometry']['orientation'] == 1
        previous = next(s for s in originals if Path(s['source']).name == report['source'])
        regions = {name: [tile['x'], tile['y'], 512, 512] for name,tile in previous['regions']['regions'].items()}
        if report['source'] == 'Ricoh-GR-IIIx.DNG':
            regions['sky'] = [2560,0,512,512]
        report['fixed_regions'] = regions
        for render in report['renders']:
            stem = f"{Path(report['source']).stem}-{int(render['ev'])}"
            images = {}
            for side in ['native','reference']:
                image = BASE / render[side]
                assert sha(image) == render[f'{side}_sha256']
                overview = (EVIDENCE if side == 'native' and render['ev'] == 0 else REVIEW) / f'{stem}-{side}-overview.png'
                run([image,'-resize','900x600',overview])
                images[f'{side}_overview'] = artifact(overview)
                crops = []
                for name,(x,y,w,h) in regions.items():
                    crop = BASE / f'{stem}-{side}-{name}.png'
                    run([image,'-crop',f'{w}x{h}+{x}+{y}','+repage',crop])
                    crops.append(crop)
                sheet = REVIEW / f'{stem}-{side}-regions.png'
                run(['montage', '-font', next((ROOT/'assets/fonts').glob('Inter-*.ttf')), *crops, '-tile','3x','-geometry','512x512+0+0',sheet])
                images[f'{side}_regions'] = artifact(sheet)
            for name in (['sky','highlight_stress'] if 'IIIx' in stem else []):
                pair = EVIDENCE / f'{stem}-{name}-pair.png'
                run([BASE/f'{stem}-native-{name}.png', BASE/f'{stem}-reference-{name}.png','+append',pair])
                images[name] = artifact(pair)
            render['review_images'] = images
    (EVIDENCE/'report.json').write_text(json.dumps(reports,indent=2)+'\n')
    (EVIDENCE/'oracle-audit.json').write_bytes((BASE/'oracle-audit.json').read_bytes())

if __name__ == '__main__':
    main()
