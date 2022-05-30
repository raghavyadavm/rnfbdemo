#!/bin/bash
set -e 


# Previous compiles may confound future compiles, erase...
\rm -fr "$HOME/Library/Developer/Xcode/DerivedData/rnfbdemo*"

# Basic template create, rnfb install, link
\rm -fr rnfbdemo

echo "Testing react-native rn69 + static frameworks"

if ! which yarn > /dev/null 2>&1; then
  echo "This script uses yarn, please install yarn (for example \`npm i yarn -g\` and re-try"
  exit 1
fi

npm_config_yes=true npx react-native init rnfbdemo --skip-install --version=0.69.0-rc.3
cd rnfbdemo

# New versions of react-native include annoying Ruby stuff that forces use of old rubies. Obliterate.
if [ -f Gemfile ]; then
  rm -f Gemfile* .ruby*
fi

# Now run our initial dependency install
yarn
# npm_config_yes=true npx pod-install

# Hermes is available on both platforms and provides faster startup since it pre-parses javascript. Enable it.
sed -i -e $'s/hermes_enabled => flags\[:hermes_enabled\]/hermes_enabled => true/' ios/Podfile  # RN69 style hermes enable
rm -f ios/Podfile??

# Apple builds in general have a problem with architectures on Apple Silicon and Intel, and doing some exclusions should help
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.aggregate_targets.each do |aggregate_target|\\\n      aggregate_target.user_project.native_targets.each do |target|\\\n        target.build_configurations.each do |config|\\\n          config.build_settings[\'ONLY_ACTIVE_ARCH\'] = \'YES\'\\\n          config.build_settings[\'EXCLUDED_ARCHS\'] = \'i386\'\\\n        end\\\n      end\\\n      aggregate_target.user_project.save\\\n    end/' ios/Podfile
rm -f ios/Podfile.??

# This is just a speed optimization, very optional, but asks xcodebuild to use clang and clang++ without the fully-qualified path
# That means that you can then make a symlink in your path with clang or clang++ and have it use a different binary
# In that way you can install ccache or buildcache and get much faster compiles...
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["CC"] = "clang"\\\n        config.build_settings["LD"] = "clang"\\\n        config.build_settings["CXX"] = "clang++"\\\n        config.build_settings["LDPLUSPLUS"] = "clang++"\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile??

# This makes the iOS build much quieter. In particular libevent dependency, pulled in by react core / flipper items is ridiculously noisy.
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["GCC_WARN_INHIBIT_ALL_WARNINGS"] = "YES"\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile??

# In case we have any patches
echo "Running any patches necessary to compile successfully"
cp -rv ../patches .
npm_config_yes=true npx patch-package

# Run the thing for iOS
if [ "$(uname)" == "Darwin" ]; then

  echo "Installing pods and running iOS app"
  export CC=clang
  export CXX=clang++
  # npm_config_yes=true npx pod-install

  #################################
  # Check static frameworks compile

  ## Per @hramos "new architecture does not support static frameworks", pursuing whether that still applies
  ## even with new architecture disabled, and/or what is left to actually support it with static frameworks...

  # Static frameworks does not work with hermes and flipper - toggle them both off again
  sed -i -e $'s/use_flipper/#use_flipper/' ios/Podfile
  rm -f ios/Podfile.??
  sed -i -e $'s/flipper_post_install/#flipper_post_install/' ios/Podfile
  rm -f ios/Podfile.??
  sed -i -e $'s/hermes_enabled => true/hermes_enabled => false/' ios/Podfile
  rm -f ios/Podfile??

  # This is how you configure for static frameworks:
  sed -i -e $'s/config = use_native_modules!/config = use_native_modules!\\\n  config = use_frameworks!\\\n  $RNFirebaseAsStaticFramework = true/' ios/Podfile
  rm -f ios/Podfile??

  # Workaround needed for static framework build only, regular build is fine.
  # https://github.com/facebook/react-native/issues/31149#issuecomment-800841668
  sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    installer.pods_project.targets.each do |target|\\\n      if (target.name.eql?(\'FBReactNativeSpec\'))\\\n        target.build_phases.each do |build_phase|\\\n          if (build_phase.respond_to?(:name) \&\& build_phase.name.eql?(\'[CP-User] Generate Specs\'))\\\n            target.build_phases.move(build_phase, 0)\\\n          end\\\n        end\\\n      end\\\n    end/' ios/Podfile
  rm -f ios/Podfile.??
  npm_config_yes=true npx pod-install

  printf "\n\n\n\n\n\nRunning iOS Static Frameworks build\n\n\n\n\n"
  npx react-native run-ios

  # end of static frameworks workarounds + test
  #############################################
fi
