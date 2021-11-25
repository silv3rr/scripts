//taken from glftpd, thnx2u2 ;p
//taken from project-zs-ng, thx

// gcc -o passchk passchk.c -lcrypto -lcrypt
// passchk <user> <passwd>

#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <string.h>
#include <stdlib.h>

#include <paths.h>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/hmac.h>

#define SHA_SALT_LEN 4

#ifndef  __USE_SVID
struct passwd pwd;
#endif

int pw_encrypt_new(const unsigned char *pwd, unsigned char *encryp, char *digest)
{
    unsigned char hexconvert[3];
    unsigned char *salt;
    int i;
    unsigned char md[SHA_DIGEST_LENGTH];
    int mdlen = SHA_DIGEST_LENGTH;

    unsigned char real_salt[SHA_SALT_LEN + 1];

    bzero(hexconvert, sizeof(hexconvert));

    salt = encryp;
    salt++;
    for (i = 0; i < SHA_SALT_LEN; i++) {
	hexconvert[0] = (*salt);
	salt++;
	hexconvert[1] = (*salt);
	salt++;
	real_salt[i] = strtol(hexconvert, NULL, 16);
    }

    PKCS5_PBKDF2_HMAC_SHA1(pwd, strlen(pwd), real_salt, SHA_SALT_LEN, 100,
			   mdlen, md);

    *digest = '$';
    digest++;
    for (i = 0; i < SHA_SALT_LEN; i++) {
	sprintf(digest, "%02x", real_salt[i]);
	digest += 2;
    }
    *digest = '$';
    digest++;
    for (i = 0; i < mdlen; i++) {
	sprintf(digest, "%02x", md[i]);
	digest += 2;
    }
    //fix the last /0 !!!
    *digest = '\0';

}


int main(int argc, char *argv[])
{
    char *crypted;
    char *hash;
    char salt[2];

    hash = "$c8aa2099$89be575337e36892c6d7f4181cad175d685162ad";

    crypted = malloc(51);
    if (!crypted) {
	printf
	    ("Ooops, couldn't allocate %d bytes of memory for hash.\n",
	     (SHA_DIGEST_LENGTH * 2 + 1));
	return 1;
    }
    pw_encrypt_new((unsigned char *) argv[2], hash, crypted);
    printf("%s:%s:0:0:0:/site:/bin/false\n", argv[1], crypted);
}

