import os
import subprocess
import sys
import tempfile
import argparse

from BuildEnvironment import run_executable_with_output


def _rewrite_p12(file_path):
    """Turn a legacy or password-protected PKCS#12 into an empty-password AES-256 archive.

    The password is APPLE_DIST_CERT_P12_PASSWORD in the environment (empty if unset).
    It is passed to openssl via env: so it is not part of the process arguments.
    """
    password = os.environ.get('APPLE_DIST_CERT_P12_PASSWORD', '')
    env = os.environ.copy()
    env['TELLOMI_P12_PASSWORD'] = password
    work = tempfile.mkdtemp(prefix='tellomi-p12-import-')
    try:
        pem = os.path.join(work, 'identity.pem')
        modern = os.path.join(work, 'modern.p12')
        read = None
        for extra in ([], ['-legacy']):
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
            if result.returncode == 0:
                read = True
                break
        if not read:
            print('Could not read {} as a modern or legacy PKCS#12.'.format(file_path))
            sys.exit(1)
        subprocess.check_call([
            'openssl', 'pkcs12', '-export',
            '-in', pem, '-out', modern,
            '-passout', 'pass:',
            '-keypbe', 'AES-256-CBC',
            '-certpbe', 'AES-256-CBC',
            '-macalg', 'SHA256',
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(modern, 'rb') as source, open(file_path, 'wb') as dest:
            dest.write(source.read())
    finally:
        subprocess.call(['rm', '-rf', work])


def _import_p12_once(file_path, keychain_name):
    return subprocess.call([
        'security', 'import', file_path,
        '-k', keychain_name,
        '-P', '',
        '-f', 'pkcs12',
        '-A',
        '-T', '/usr/bin/codesign',
        '-T', '/usr/bin/security',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def import_p12(file_path, keychain_name):
    # `security import` on Xcode 27 accepts an empty-password AES-256 archive and
    # rejects OpenSSL -legacy (RC2). A password-protected or legacy archive is
    # rewritten once, then imported. The password never appears on the command line.
    if _import_p12_once(file_path, keychain_name) == 0:
        return
    _rewrite_p12(file_path)
    if _import_p12_once(file_path, keychain_name) != 0:
        print('security import failed for {}'.format(file_path))
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
