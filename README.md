# Installing arbitrary addons into Fenix
Well, nearly arbitrary, anyway - they still have to be signed by Mozilla, not be legacy extensions, etc., just like in desktop Firefox. But it is possible to get around Mozilla's tiny allow-list for Fenix extensions, without having to:

- Switch to the Beta or Nightly version of Firefox, or one of the forks like Fennec F-Droid, Iceraven, or Mull
- Move all your data over to that other browser
- Set up an account on AMO
- Create a publicly visible addon collection
	- Only be able to get up to 50 addons to show up
	- Only be able to use addons that are hosted on AMO
- Set whichever Firefox variant you chose to use that addon collection

I stumbled across [a comment on Hacker News](https://news.ycombinator.com/item?id=29797116) explaining how to change what addons Firefox thinks are on the list, using root access.[^hn] Basically, Firefox fetches the list from Mozilla's servers, and caches it locally as an ordinary JSON file. So by overwriting that file with another collection, you can make Firefox think the list contains whatever you want - and by setting its modification date way into the future, you can keep it from expiring and being replaced with a fresh copy of the real list.

Having learned that this was possible, I began trying to find a way to do this without root. After a failed attempt at using uBlock Origin to replace the list[^ubo], and a technically successful but not particularly practical proof-of-concept using mitmproxy to impersonate services.addons.mozilla.org[^mitm], I realized that if I could connect to the remote debugging interface (e.g. from desktop Firefox), and inspect one of Fenix's privileged pages, I could use Mozilla's internal APIs to access the filesystem as if I were Firefox, and write and touch the cache file that way.

I also discovered that I could bypass the 50-addon limit by splicing together all the pages of the addon collection before injecting it. And I could even make up entries for `.xpi` files that weren't hosted on addons.mozilla.org, and they'd install (and auto-update) just fine!

It's not exactly _easy_, but at least it's _possible_.

If you have Termux, and either Termux:X11 or a VNC-based X11 setup, and have wireless ADB turned on, you can actually do all this from the same Android device that the target Firefox is on.

If you're already using Nightly, Beta, or a fork, but still want more flexibility than the builtin custom-collection option provides, these instructions should work there too. Just change `org.mozilla.firefox` to the bundle ID for the browser you're using. (Iceraven, however, has a slight complication - it's based on an older version of the relevant code, and wants all the names and descriptions to be localized. [TODO explain what needs to be changed to make this work in Iceraven])

The usual disclaimers: use this info at your own risk, make sure you trust whatever addons you're putting in, some addons just plain won't work (missing APIs, bugs, whatever), read and think carefully before pasting in any code from here, it's not my fault if your Firefox goes boom, etc.

## Preparing the list

### To create the list from an existing collection on AMO (e.g. [Iceraven's list](https://addons.mozilla.org/en-US/firefox/collections/16201230/What-I-want-on-Fenix/)):

1. Go to `https://services.addons.mozilla.org/api/v4/accounts/account/(user name or ID)/collections/(collection name or ID)/addons/?page_size=50&sort=-popularity&lang=en-US`, and save it.
	- Change `lang` to the language you want addon names and descriptions in.
	- `sort` can be one of:
    	- `popularity` (weekly downloads ascending)
    	- `-popularity` (" descending)
    	- `name` (A-Z)
    	- `-name` (Z-A)
    	- `added` (oldest-newest)
    	- `-added` (newest-oldest)
2. Go to the next page. Copy the contents of the 'results' array, and append them to the previous page.
3. Repeat until you run out of pages.

If you have `jq` installed, you can just use [get-addon-collection.sh](./get-addon-collection.sh). (Should work in both `bash` and `zsh`.)

```shell
$ ./get-addon-collection.sh user-name-or-ID collection-name-or-ID > addons.json
$ # (defaults to Iceraven list if not specified)
```

### To add addons without creating an AMO collection:

1. Start with either an existing addon collection saved using the above instructions, or an 'empty' collection file:
```json
{
	"results": []
}
```
2. Find the URL for the first addon you want to add to the list, and extract the 'slug' (e.g. `https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/` → `ublock-origin`)
3. Go to `https://services.addons.mozilla.org/api/v4/addons/addon/(slug goes here)/?lang=en-US`, and copy the _entire_ result object.
	- Change `lang` to the language you want addon names and descriptions in.
4. Prepend an object to the 'results' array that looks like:
```jsonc
{
	"addon": {/* the addon object you copied */},
	"notes": null
}
```
5. Repeat for the rest of the addons you want to append.

### To add `.xpi` files from sources other than AMO:

Similar to the previous set of instructions, but instead of getting the addon object from SAMO, you build one with [the minimum fields needed by Fenix](https://github.com/mozilla-mobile/firefox-android/blob/81f18d929bed6e0d82f0d7e80e52531add87c5d0/android-components/components/feature/addons/src/main/java/mozilla/components/feature/addons/amo/AddonCollectionProvider.kt#L316-L343):

```json
{
	"guid": "some-addon@example.com",
	"authors": [],
	"categories": {"android": []},
	"created": "1970-01-01T00:00:00Z",
	"last_updated": "1970-01-01T00:00:00Z",
	"icon_url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+P+/HgAFhAJ/wlseKgAAAABJRU5ErkJggg==",
	"current_version": {
		"version": "0.0.0.0",
		"files": [{
			"id": -1,
			"url": "https://example.com/some-addon-1.2.3.4.xpi",
			"permissions": ["https://unknown-permissions.use-at-your-own-risk.invalid/*"],
		}],
	},
	"name": "Some Addon",
	"description": "Long description goes here.",
	"summary": "Short description",
	"ratings": {
		"average": 0,
		"bayesian_average": 0,
		"count": 0,
		"text_count": 0
	},
	"weekly_downloads": 0
}
```

The important ones to get right here are `guid` (which is how Fenix decides that the installed addon matches one on the list when it checks later on, so it doesn't disable it), `name` (so you can identify it in the addon manager), and `current_version.files[0].url` (so it can actually install it the first time).

Everything else in that example is just a placeholder to make sure the cache file gets loaded properly. The `icon_url` is a 1x1 transparent PNG, to keep Firefox from showing the icon of a random unrelated addon.

Wrap it up in an `{addon: {...}, notes: null}` object and prepend it to `results`.

As long as the addon has a proper update manifest, it will auto-update like any other addon without having to change its URL or version in the list.

## Injecting the list

1. Make sure some form of ADB - either USB, old-style `adb wifi`, or Android 11-style Wireless Debugging, doesn't matter - is enabled on your device.
2. Make sure "Remote debugging via USB" is enabled in Android Firefox's preferences. (Yes, even if you're not technically using USB.)
3. Connect to ADB. In desktop Firefox, go to `about:debugging`, and select the target Firefox.
4. Inspect a privileged page:
	1. Either bring up `about:about`, `about:support`, or another privileged `about:` page, and connect to it…
	2. Or scroll to the very bottom, select 'Multiprocess Toolbox' to look at the main process, and switch to a 'frame' with the URL `chrome://geckoview/content/geckoview.xhtml`. This way you don't have to bring up any specific page on Fenix. However, it will (as of this writing) throw harmless-but-annoying errors on nearly every keypress, as it tries and fails to do autocompletion.
5. Switch to the Console tab, and find the addon collection cache file that needs to be overwritten:
```js
(await IOUtils.getChildren('/data/data/org.mozilla.firefox/files')).filter(x => x.match(/_components_addon_collection_.*\.json$/))
```
6. Copy the path name that the above code returns. (There should only be one.) Currently the file name is `mozilla_components_addon_collection_??_Extensions-for-Android.json`, where `??` is your base language code, e.g. `en`. Mozilla seems to change addon collections evey once in a while (this is at least their third one), so this file name may be different at some point. (When this happens, Firefox will stop using your modified cache file and revert to the official list.)
7. Also copy the contents of your addon list file that you build earlier.
8. In the Console, write and touch the file:
```js
const myAddonCache = '/data/data/org.mozilla.firefox/files/(whatever).json';
await IOUtils.writeJSON(myAddonCache, {/* paste the object from your new addon list file in place of these braces */});
const myFakeModTime = new Date();
myFakeModTime.setFullYear(myFakeModTime.getFullYear() + 100);
await IOUtils.setModificationTime(myAddonCache, +myFakeModTime);
```
9. Open up the addon manager in Android Firefox. It should immediately use the new list. If it doesn't, then either the wrong file was written, or Firefox thinks the contents were invalid, threw them out, and got a fresh copy from Mozilla.

## Notes

Yeah… it's a pain. I've written a Node.JS script that handles the entire process of building and injecting a custom addon list, and am hoping to release it soon… once I can wrap my head around the license situation and be sure it's safe to release:
- I didn't really copy Mozilla code _per se_, but I dug through a _lot_ of Mozilla code while piecing together how to use the (old, XPCOM-based) file API (before I found out about IOUtils and rewrote based on that), so is my code based on Mozilla's code enough to need to be MPL'd?
- I'm using [Foxdriver](https://github.com/saucelabs/foxdriver) to talk to Firefox's remote debugging interface. I'm patching it a bit to be able to do what I need - at runtime, using [Pirates](https://github.com/danez/pirates) (more because I'm too lazy to embed and maintain a fork than because of anything license-related). But I'm embedding little snippets of Foxdriver's code so that I can recognize them in the patching function, and Foxdriver is Apache-2.0-licensed. How does that affect things? Do I need to split those patches into a separate file from the other code?
- Do I need to retcon a license file, copyright/license header comments, etc. into the Git history using `git-filter-repo`? Do I need to just start the history over with a new, properly licensed initial commit?

And so on and so forth… It's entirely possible that I'm making it more complicated than it needs to be, but I _really_ don't want to mess it up.

[^hn]: Warning: the command in that comment has an extra `.mozilla` in the path name.

[^ubo]: Using a custom [userResourcesLocation](https://github.com/gorhill/uBlock/wiki/Advanced-settings#userresourceslocation) to let me substitute the modified addon list data. I didn't really expect this to work - addons can't mess with addons.mozilla.org, so surely services.addons.mozilla.org would also be protected. But services.addons.mozilla didn't seem to be on the restricted domain list, and I couldn't find anything indicating that subdomains were automatically protected. And how could I ignore the possibility of using the top addon on the list - the one addon that Mozilla would _never_ remove from the list - to defeat the list? Sadly, whether because it's a restricted domain, or because Fenix is just going through a different code path when it gets the list, uBlock Origin proved unable to tamper with those requests.

[^mitm]: Oddly enough, even though uBlock Origin can't mess with that request, FoxyProxy Standard _can_. Once I went to Firefox's secret settings and allowed user CAs, it worked, and I could get non-listed addons loaded this way. But I didn't like leaving a custom CA (which I almost certainly wasn't securing as well as a real CA) installed all the time, which meant the process looked like: 1. Install mitmproxy's root CA into Android. 2. Turn on Firefox secret settings, and enable user CAs. 3. Fire up mitmproxy. 4. Switch Firefox's language and go to addon manager, to reload the list. 5. (occasionally) Oops, it _also_ has it cached at the browser level - go to Android settings, and clear Firefox's cache from there. 6. Switch Firefox back to English, and open the addon manager again. 7. Go back to secret settings and turn off user CAs. 8. Go back to Android settings and uninstall the CA - from two different places for some reason. _And that doesn't even do the 'set the modification date' part,_ meaning I had to do that whole process fairly often… and as I would later discover, temporarily setting the system date forward to fix the modification date is a bad idea, because Firefox then saves that future date as the last time it checked for _addon updates_. I was only able to fix that because I had figured out the console thing, and could directly zap the database where that date had gotten stored.
