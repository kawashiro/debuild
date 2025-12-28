# debuild - quick and dirty script to host Debian packages local repository

---

# Build and install

## Requirements

To run this script and host your repo, you will need:

* Install any web server and configure it's root to your repo directory
* `apt install dpkg-dev fakeroot rng-tools docker-ce`

## Repo preparation

1. Generate GPG keys if you don't have one already:
```bash
# Create keys generation script
cat >~/.gnupg/aptRepo <<EOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 3072
Subkey-Type: ELG-E
Subkey-Length: 3072
Name-Real: apt tech user
Name-Comment: without passphrase
Name-Email: apt@email.non
Expire-Date: 0
%echo done
EOF
# Generate the keys
gpg --batch --gen-key ~/.gnupg/aptRepo
# Check the generated key
gpg --list-keys
# Export the public key
gpg --export -a HASH > /path/to/repo/root/repo.gpg
```
2. Create debuild.conf file in the script's directory:
```bash
# Provide the path to your local repository directory and GPG key for signing the packages.
export APT_REPO_DIR=""
export GPG_KEY=""
```
3. Run the script to build and publish packages:
```bash
./debuild.sh
```
4. Configure your clients to use the repository by adding the following lines to their `/etc/apt/sources.list` file:
```bash
# Import the key
wget -qO - http://your-repo/xxxxx.gpg | gpg --dearmor -o /usr/share/keyrings/your-repo-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/your-repo-keyring] http://your-repo/ ./" > /etc/apt/sources.list.d/your-repo.list
```

5. And that's it!
