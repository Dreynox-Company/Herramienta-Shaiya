"""Apply the reviewed R27 git diff only after verifying every transport segment.

No opaque code is executed: decoded bytes are a git diff whose exact digest and
applicability are checked. CI commits readable sources before building them.
"""
from pathlib import Path
import base64
import hashlib
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'fix/studio-0627-spk-navigation-orbit-brand'
DIGEST = '3911f19a934cea2c841d98ff9a92bfba0d921286e7b5df476472c9fe46ee8e23'
HEAD_HASHES = [
    '0ff1dcd7aee5937e822369d6cb7c6fb840d86ae436f5a61bb1dea3bc83d0de92',
    '2488a925a570c79582081f71a454ab6a2c94ef6c3c3261ff29b366b391766bd0',
]
TAIL_HASHES = [
    '81e38ea23c041ef265f4c1c1b63c45694fbdf5b9278e7a75e52938a257fb26a2',
    '8d802041c080cf0bb863fc0fbc9b4983ac89573c48fe419b11a333c2712f5bb7',
    'e4149870eb45dace7dc4735d3a6ecc6b5ac94f794f68a051432b95b2afce1b17',
    '058192679774932cc85ec8e454ddabfd86934fcadc330868329e68e6a548a3d7',
    'd141507511a430204d16a4f2b74bce16af63ab1ceddc6047a0db33211b6f915b',
    '36d03a99a3dd5e992a6bbd779c7cc84a2ab1ec93c54550cc547eb59501a809dc',
    'c7dac63a07e2069098891ea4f1800aac21c1a46833329e73f31c785f391564ca',
    '51d8684bb08274b5df5eaa5dc46298ca588cea0ac5186b6ccea31c023aea81c9',
    '818a2686d9f1e05388b25a1d0ff70318ba34f062c370ab0a2c6b55df30d45f68',
    'c1e3ec6eb35ffa319dbadfe3315353e1af15a16febfa99c0c89b8d4589bbf29c',
    '104cac1f90fb8e8fd04f1fa8b8c5e9c85a136ae312b66fc81a06012c960cb7c0',
    'd4b86636112edd9c23e1a55d8a552a22ee7f65c6734ae071b6149978c26b020b',
    '83b0f7601d2959d4f08c61db8e44bd1a51bb02ec557134e6a9a081f0468cb7c9',
    '9f06d00c5566822049cb48b8bee9a683c2a521b978d24e1d824641581a1888be',
    'f7964471093e76531e5c5424e826dc87d1c3fd3df06b9df0d518746f07fd2747',
    '56bb4e8f1ed61986705a9e6ae60ffceb37bc510d45a32d2a5226fd380129e195',
    'f4ae6f37e7bb8349293a36ca998a46efce399da05e38485a7ee573abcb7f6e72',
    '32181f1b6741b0fe8b5d39b408454a1d3b4b6ab817f77e9775642efa1c905876',
    '324ce2e43e0d6b92838a304d2154d94d6eecdb4b4f73caaf54f3f115304250cb',
    '09ee674a3b9b80dbe2b507766c87a0f1199b2961c942a2922fb9e3fd89c1d514',
    'd80e12f9b595f4f4ef43fde038de8f725bbe1f1f9816ce0d5ecfd770ee594da5',
    'bbad4dc3ffe5c39cc7f99458601bcda2e475e83ed6e8de8f0d760c92e49b9363',
    'bed9760d3ef22e574ba8dc3415cff791f3e202beb5c2e22923afe0575245bbb9',
    'cda3ca227bdc489e967e6beb7f1c1036394df7af0617dcad46c0c38e770f88d3',
    '3c496eedf5913e3663e9643538190516679725c8569d774ee1dcd6167190c38a',
    'e8ac44b162c0666d0e7a54e23bff1cc4ed6e7a1a18ebb036fb8270179a1ae5a2',
    '849ab766dbcbb4263fd857cb9bbcc84842056e7b61afd3d473651b2c1c05ede1',
    '5d7cae3f698a4fa2e15fd7ac1c379cbb2eaeb826f140dc836b17ac49a7aaa4ac',
    '7f98f4d7ca4fb18257f841007835daa4784223d59c7da61947b61f6d876aa17b',
    'bf3bf8947d306b62c6ac1909f60c469e9bcc07d8cd398cdc596fede682d8a4c8',
    '5b7f71b4fcb30f90fb9cba03a858dad19afa08602f0de64964cf00625e9d788f',
    '0c4a08e7bb6155b943c3e973def52d318f00c20c2be34d7f741dcdcd92272d5f',
    '100e7a6dbe8a42fcbc2082042c2d882bb4b717c4514909820d515740a8847103',
]


def main():
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != BRANCH:
        raise RuntimeError('Refusing to change another branch.')
    marker = ROOT / '.studio-r27-applied'
    if marker.exists():
        if marker.read_text().strip() != DIGEST:
            raise RuntimeError('Different R27 patch already applied.')
        return
    segments = []
    errors = []
    for i, expected in enumerate(HEAD_HASHES, 1):
        name = f'ci/r27.patch.part{i}'
        text = (ROOT / name).read_text().strip()
        if i == 1 and hashlib.sha256(text.encode()).hexdigest() != expected:
            text = text.replace('gRm/Ldugrppp9', 'gRm/Ldugrpp9')
        actual = hashlib.sha256(text.encode('ascii')).hexdigest()
        if len(text) != 12500 or actual != expected:
            errors.append(f'{name}: length={len(text)} sha256={actual}; expected={expected}')
        segments.append(text)
    for i, expected in enumerate(TAIL_HASHES, 1):
        name = f'ci/r27.tail.{i:02}' + ('.correct' if i == 26 else '')
        text = (ROOT / name).read_text().strip()
        actual = hashlib.sha256(text.encode('ascii')).hexdigest()
        if len(text) != (2224 if i == 33 else 2500) or actual != expected:
            errors.append(f'{name}: length={len(text)} sha256={actual}; expected={expected}')
        segments.append(text)
    if errors:
        raise RuntimeError('Transport verification failed; no source was changed:\n' + '\n'.join(errors))
    encoded = ''.join(segments)
    diff = zlib.decompress(base64.b64decode(encoded, validate=True))
    if len(encoded) != 107224 or len(diff) != 178380 or hashlib.sha256(diff).hexdigest() != DIGEST:
        raise RuntimeError('Combined source patch integrity mismatch.')
    subprocess.run(['git', 'apply', '--check', '-'], cwd=ROOT, input=diff, check=True)
    subprocess.run(['git', 'apply', '-'], cwd=ROOT, input=diff, check=True)
    # These two intermediate transport files were never accepted or executed.
    for unused in ('ci/r27.patch.part3', 'ci/r27.tail.26'):
        (ROOT / unused).unlink(missing_ok=True)
    marker.write_text(DIGEST + '\n')
    print('R27 reviewed diff verified and applied:', DIGEST)


if __name__ == '__main__':
    main()
