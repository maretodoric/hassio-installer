#!/usr/bin/env python3

import datetime, pdb
import argparse, requests
import sys, os, json, hashlib

from subprocess import Popen, PIPE

SD = os.path.dirname(os.path.realpath(__file__))
os.chdir(SD)

class color:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def iprint(m):
    print(f"{color.OKGREEN}{color.BOLD}>>>{color.ENDC} {m}")

def wprint(m):
    print(f"{color.WARNING}{color.BOLD}>>>{color.ENDC} {m}")

def eprint(m):
    print(f"{color.FAIL}{color.BOLD}>>>{color.ENDC} {m}")

def fprint(m, rc=1):
    eprint(m)
    sys.exit(rc)

def dprint(m):
    if args.verbose:
        print(f"{color.BOLD}>>> {m}{color.ENDC}")

def sh(c, verbose=None):
    if not verbose:
        verbose = args.verbose

    try:
        dprint(f"Running command: {c}")
        proc = Popen(c.split(), stdout=PIPE, stderr=PIPE)
        if verbose:
            for i in proc.stdout:
                print(i.decode("utf-8"), end='')
            proc.wait()
            rc = proc.poll()
            if rc > 0:
                fprint(f"Command: {c} finished with exit code: {rc}.", rc=rc)
        else:
            out, err = proc.communicate()
            rc = proc.poll()
            if rc > 0:
                fprint(f"Command: {c} failed with exit code: {rc}. Output:\n{err.decode('utf-8')}", rc=rc)
    except FileNotFoundError:
        fprint(f"Command not found: {c.split()[0]}")

def getIsoFileName():
    global VERSION
    VERSION="test"
    if args.release or args.release_only:
        dprint(f"Opening {SD + '/vols/build/aports/custom-scripts/installer.sh'} to extract Release Version...")
        with open(SD + "/vols/build/aports/custom-scripts/installer.sh") as f:
            for i in f:
                if "export INSTALLER_VERSION" in i:
                    i = i.replace("\n", "")
                    dprint(f"Found line: '{i}', extracting version...")
                    VERSION=i.split("=")[-1].replace('"','').replace('\n','')
                    break
        if not VERSION or VERSION == "test":
            fprint("Unable to extract Release Version.")

    isopath=SD + f"/vols/build/iso/hassio_installer-{VERSION}-x86_64.iso"
    isoname=f"hassio_installer-{VERSION}-x86_64.iso"
    return (isopath, isoname)

def getGHAuthHeader():
    token = os.getenv("GITHUB_MASTER_KEY")
    dprint(f"Extracting Github token from Environment Variable, got: {token}")

    if isinstance(token, type(None)):
        if not args.github_token:
            fprint("Failed to get github auth token from GITHUB_MASTER_KEY and --github-token not specified")
        else:
            token = args.github_token

    header = { "Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}" }
    dprint(f"Returning header: {header}")
    return header

def release():
    iprint("Creating release, generating GitHub Auth Header...")
    headers=getGHAuthHeader()
    dprint(f"Obtained headers:\n{color.ENDC}{json.dumps(headers, indent=4)}")
    rnfile = "release_notes.txt"
    iprint("Getting file and version name")
    isopath, isoname = getIsoFileName()
    global VERSION
    dprint(f"Obtained file name: {isoname} and release version: {VERSION}")

    if not os.path.exists(isopath):
        fprint(f"ISO Image does not exist at path: {isopath}")
    
    if os.path.exists("CHANGELOG.md") and not os.path.exists(rnfile):
        dprint("Found CHANGELOG.md, using it as a stub for release notes.")
        sh(f"cp CHANGELOG.md {rnfile}")

    input(f"Upon pressing ENTER, vim editor will open {rnfile} that you can edit which will be used as release notes.")
    os.system(f"vim {rnfile}")

    # Exit if release notes file does not exist, this means that CHANGELOG.md does not exist an changes were not saved in previous editor.
    if not os.path.exists(rnfile):
        fprint("Release Notes file does not exists! Exiting.")
    else:
        with open(rnfile) as f:
            body = f.read()

    iprint("Creating request body")
    payload = {
            "tag_name": VERSION,
            "target_commitish": "main",
            "name": f"Release {VERSION}",
            "body": body,
            "draft": False,
            "prerelease": False,
            "generate_release_notes": False
    }
    dprint(f"Request body:\n{json.dumps(payload, indent=4)}")
    iprint("Sending payload to GitHub...")
    release = requests.post("https://api.github.com/repos/maretodoric/hassio-installer/releases", headers=headers, json=payload)
    if release.status_code == 201:
        upload_url = release.json()["upload_url"].replace("{?name,label}","")
        release_id = release.json()["id"]
        html_url = release.json()["html_url"]

        # Load iso file
        dprint("Loading ISO Image to buffer...")
        sha256_hash = hashlib.sha256()
        with open(isopath, "rb") as f:
            isoasset = f.read()
            dprint("Calculating sha256 hash...")
            f.seek(0)
            f.flush()
            for byte_block in iter(lambda: f.read(4096),b""):
                sha256_hash.update(byte_block)

        dprint(f"Creating hash file with value: {sha256_hash.hexdigest()}")
        with open(isopath + ".sha256", "w") as f:
            f.write(sha256_hash.hexdigest())

        with open(isopath + ".sha256", "rb") as f:
            shaasset = f.read()

        iprint(f"Release with ID: {release_id} and version: {VERSION} successfully created! Pushing ISO Image...")
        dprint(f"Pushing ISO Image using URL: {upload_url}")
        asset = requests.post(upload_url + f"?name={isoname}", headers={ "Authorization": headers["Authorization"], "Content-Type": "application/octet-stream" }, data=isoasset)
        shaasset = requests.post(upload_url + f"?name={isoname}.sha256", headers={ "Authorization": headers["Authorization"], "Content-Type": "text/plan" }, data=shaasset)
        if asset.status_code == 201:
            iprint(f"Asset successfully uploaded, link to release: {html_url}")
        else:
            eprint(f"Failed to upload ISO Image as Asset! Response:\n{json.dumps(asset.json(), indent=4)}")
            requests.delete(f"https://api.github.com/repos/maretodoric/hassio-installer/releases/{release_id}", headers=headers)
            requests.delete(f"https://api.github.com/repos/maretodoric/hassio-installer/git/refs/tags/{VERSION}", headers=headers)
            iprint("Falling back created release.")
            sys.exit(1)
    else:
        fprint(f"Failed to create release! Response:\n{color.ENDC}{json.dumps(release.json(), indent=4)}")

    os.remove(rnfile)

def buildIso():
    if args.release:
        VARS="-e RELEASE=1"
        msg = "Started building Tagged ISO image and publish release..."
    else:
        VARS=""
        msg = "Started building ISO image ..."

    _cmd = f"docker run -it --rm -v {SD}/vols/build:/build -v {SD}/vols/tmp:/tmp -a STDOUT -a STDERR {VARS} alpine-build-iso {cmd}"
    if cmd:
        iprint("Custom command requested, not automatically building ISO")
        sys.exit(os.system(_cmd))
    else:
        iprint(msg)

    start = datetime.datetime.now()
    sh(_cmd)
    if not cmd:
        end = datetime.datetime.now() - start
        iprint(f"Build time took: {end}")

    isopath, isoname = getIsoFileName()
    if not os.path.exists(isopath):
        fprint(f"Unable to find ISO at path: {isopath}, build possibly failed")

    # Handle --send-to argument
    if args.upload_to:
        if ":" in args.upload_to:
            host = args.upload_to
        else:
            host = args.upload_to + ":"

        iprint(f"Upload of ISO Image to remote host requested, sending to {host}")
        sh(f"scp {isopath} {host}")

    if args.release:
        release()

parser = argparse.ArgumentParser(description="Helper script to build docker image for building ISO, and for building ISO itself")
parser.add_argument("--build-dockerimage", dest="build_dockerimage", action="store_true", help="Created docker image that is used for building ISO")
parser.add_argument("--build-iso", dest="build_iso", action="store_true", help="Build Home Assistant Installer OS - Make sure image is created. This is default, however needs to be specified if you with to build ISO after running --build-dockerimage")
parser.add_argument("--rm", dest="remove", action="store_true", help="Will remove ISO Image after creation")
parser.add_argument("--send-to", "--upload-to", dest="upload_to", type=str, help="Sends ISO Image to selected host, you can use user@host or just host - will use SCP and honor ~/.ssh/config")
parser.add_argument("--release", dest="release", action="store_true", help="This will build and tag the ISO with version instead of 'test'. Version will be used from vols/build/aports/custom-scripts/installer.sh")
parser.add_argument("--release-only", dest="release_only", action="store_true", help="This will only publish release to GitHub, will not build ISO. Expects that ISO is already created")
parser.add_argument("--cmd", dest="cmd", nargs="*", default="", help="Command to execute inside container, does not actually build ISO unless manual build is triggered inside container.")
parser.add_argument("--fix-perms", dest="fix_perms", action="store_true", help="Fix permissions for volume in case you have those errors")
parser.add_argument("-v", "--verbose", dest="verbose", action="store_true", help="Show verbose output")
args = parser.parse_args()

# Make sure cmd is propery formatted
if isinstance(args.cmd, list):
    cmd = " ".join(args.cmd)
else:
    cmd = ""

# Handle --build-dockerimage arg
if args.build_dockerimage:
    iprint("Building Docker Image...")
    sh("docker build -t alpine-build-iso .")

# Handle --fix-perms
if args.fix_perms:
    iprint("Fixing permissions")
    sh(f"chmod -v 777 {SD}/vols/tmp", verbose=True)
    sh(f"chown -cR 1000:300 {SD}/vols/build", verbose=True)

if args.release_only:
    release()
elif args.build_dockerimage:
    if args.build_iso:
        buildIso()
else:
    buildIso()

# Handle --rm argument
if args.remove:
    iprint("Auto-removal of created ISO requested, removing ...")
    os.remove(getIsoFileName()[1])

iprint("Work completed")
