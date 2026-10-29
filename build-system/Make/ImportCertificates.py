import os
import subprocess
import sys
import tempfile
import argparse

from BuildEnvironment import run_executable_with_output


def _security_import(file_path, keychain_name, password):
    result = subprocess.run(
        [
            'security', 'import', file_path,
            '-k', keychain_name,
            '-P', password,
            '-f', 'pkcs12',
            '-A',
            '-T', '/usr/bin/codesign',
            '-T', '/usr/bin/security',
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    detail = result.stderr.decode('utf-8', errors='replace').strip()
    if password:
        detail = detail.replace(password, '***')
    return result.returncode, detail


def _candidate_passwords():
    passwords = ['']
    supplied = os.environ.get('APPLE_DIST_CERT_P12_PASSWORD', '')
    if supplied and supplied not in passwords:
        passwords.append(supplied)
    return passwords


def _read_identity_pem(file_path, password):
    env = os.environ.copy()
    env['TELLOMI_P12_PASSWORD'] = password
    for extra in ([], ['-legacy']):
        work = tempfile.mkdtemp(prefix='tellomi-p12-read-')
        pem = os.path.join(work, 'identity.pem')
        result = subprocess.run(
            [
                'openssl', 'pkcs12', '-in', file_path,
                '-passin', 'env:TELLOMI_P12_PASSWORD',
                '-nodes', '-out', pem,
            ] + extra,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0 and os.path.exists(pem):
            with open(pem, 'r', encoding='utf-8', errors='replace') as handle:
                text = handle.read()
            if 'PRIVATE KEY' in text:
                return work, pem
        subprocess.call(['rm', '-rf', work])
    return None, None


def _export_variants(pem_path, destination):
    variants = [
        ['-keypbe', 'AES-256-CBC', '-certpbe', 'AES-256-CBC', '-macalg', 'SHA256'],
        ['-keypbe', 'AES-256-CBC', '-certpbe', 'AES-256-CBC', '-macalg', 'SHA1'],
        ['-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'SHA1'],
        ['-legacy'],
    ]
    written = []
    for extra in variants:
        out = destination + '.' + str(len(written)) + '.p12'
        result = subprocess.run(
            [
                'openssl', 'pkcs12', '-export',
                '-in', pem_path,
                '-out', out,
                '-passout', 'pass:',
            ] + extra,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            written.append(out)
    return written


def import_p12(file_path, keychain_name):
    # Try the archive as provided: empty password, then the secret password.
    # openssl -legacy exports often import only with that password. Rewriting
    # first to an empty-password AES archive made `security import` reject the
    # file and then the fallback could not open it with the original password.
    errors = []
    for password in _candidate_passwords():
        status, detail = _security_import(file_path, keychain_name, password)
        if status == 0:
            return
        label = 'empty password' if password == '' else 'supplied password'
        errors.append('{}: {}'.format(label, detail or 'security import failed'))
    work, pem = _read_identity_pem(file_path, '')
    if pem is None:
        supplied = os.environ.get('APPLE_DIST_CERT_P12_PASSWORD', '')
        if supplied:
            work, pem = _read_identity_pem(file_path, supplied)
    if pem is None:
        print('Could not read {} as a modern or legacy PKCS#12.'.format(file_path))
        for line in errors:
            print(line)
        sys.exit(1)
    try:
        for variant in _export_variants(pem, os.path.join(work, 'modern')):
            status, detail = _security_import(variant, keychain_name, '')
            if status == 0:
                return
            errors.append(detail or 'rewritten PKCS#12 was rejected')
    finally:
        subprocess.call(['rm', '-rf', work])
    print('security import failed for {}'.format(file_path))
    for line in errors:
        print(line)
    sys.exit(1)

def import_certificates(certificatesPath):
    if not os.path.exists(certificatesPath):
        print('{} does not exist'.format(certificatesPath))
        sys.exit(1)

    keychain_name = 'temp.keychain'
    keychain_password = 'secret'

    existing_keychains = run_executable_with_output('security', arguments=['list-keychains'], check_result=True)
    if keychain_name in existing_keychains:
        # The keychain name is required. Without it `security` fails with
        # "SecKeychainDelete: The specified keychain is not a valid keychain file",
        # which only happens on a second build inside one VM -- unreachable while every
        # build got a fresh ephemeral VM, and hit on every reuse of a persistent one.
        run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=True)

    run_executable_with_output('security', arguments=[
        'create-keychain',
        '-p',
        keychain_password,
        keychain_name
    ], check_result=True)

    existing_keychains = run_executable_with_output('security', arguments=['list-keychains', '-d', 'user'])
    existing_keychains.replace('"', '')

    run_executable_with_output('security', arguments=[
        'list-keychains',
        '-d',
        'user',
        '-s',
        keychain_name,
        existing_keychains
    ], check_result=True)

    run_executable_with_output('security', arguments=['set-keychain-settings', keychain_name])
    run_executable_with_output('security', arguments=['unlock-keychain', '-p', keychain_password, keychain_name])

    for file_name in os.listdir(certificatesPath):
        file_path = certificatesPath + '/' + file_name
        if file_path.endswith('.p12'):
            import_p12(file_path, keychain_name)
        elif file_path.endswith('.cer'):
            run_executable_with_output('security', arguments=[
                'import',
                file_path,
                '-k',
                keychain_name,
                '-P',
                '',
                '-T',
                '/usr/bin/codesign',
                '-T',
                '/usr/bin/security'
            ], check_result=False)

    run_executable_with_output('security', arguments=[
        'import',
        'build-system/AppleWWDRCAG3.cer',
        '-k',
        keychain_name,
        '-P',
        '',
        '-T',
        '/usr/bin/codesign',
        '-T',
        '/usr/bin/security'
    ], check_result=False)

    run_executable_with_output('security', arguments=[
        'set-key-partition-list',
        '-S',
        'apple-tool:,apple:',
        '-k',
        keychain_password,
        keychain_name
    ], check_result=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(prog='build')

    parser.add_argument(
        '--path',
        required=True,
        help='Path to certificates.'
    )

    if len(sys.argv) < 2:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()

    import_certificates(args.path)
