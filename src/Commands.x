#import "Enmity.h"
#import <LocalAuthentication/LocalAuthentication.h>

// Create a response to a command
NSDictionary* createResponse(NSString *uuid, NSString *data) {
  NSDictionary *response = @{
    @"id": uuid,
    @"data": data
  };

  return response;
}

// Send a response back
void sendResponse(NSDictionary *response) {
  NSError *err;
  NSData *data = [NSJSONSerialization
                    dataWithJSONObject:response
                    options:0
                    error:&err];

  if (err) {
    return;
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSString *responseString = [NSString stringWithFormat: @"%@%@", ENMITY_PROTOCOL, [json stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
  NSURL *url = [NSURL URLWithString:responseString];

  NSLog(@"json: %@", json);

  [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

// Validate that a command is using the Enmity scheme
BOOL validateCommand(NSString *command) {
  BOOL valid = [command containsString:@"enmity"];

  if (!valid) {
    NSLog(@"Invalid protocol");
  }

  return valid;
}

// Clean the received command
NSString* cleanCommand(NSString *command) {
  NSString *json = [[command stringByReplacingOccurrencesOfString:ENMITY_PROTOCOL withString:@""] stringByRemovingPercentEncoding];

  NSLog(@"json payload cleaned: %@", json);

  return json;
}

// Parse the command
NSDictionary* parseCommand(NSString *json) {
  NSURLComponents* components = [[NSURLComponents alloc] initWithString:json];
  NSArray *queryItems = components.queryItems;

  NSMutableDictionary *command = [[NSMutableDictionary alloc] init];

  for (NSURLQueryItem *item in queryItems) {
    if ([item.name isEqualToString:@"id"]) {
      command[@"id"] = item.value;
    }

    if ([item.name isEqualToString:@"command"]) {
      command[@"command"] = item.value;
    }

    if ([item.name isEqualToString:@"params"]) {
      command[@"params"] = [item.value componentsSeparatedByString:@","];
    }
  }

  return [command copy];
}

BOOL handleThemeInstall(NSString *uuid, NSURL *url, BOOL exists, NSString *themeName) {
  BOOL success = installTheme(url);
  if (success) {
    if ([uuid isEqualToString:@"-1"]) return true;

    sendResponse(createResponse(uuid, exists ? @"overridden_theme" : @"installed_theme"));
    return true;
  }

  if ([uuid isEqualToString:@"-1"]) {
    alert([NSString stringWithFormat:@"An error happened while installing %@.", themeName]);
    return false;
  }

  sendResponse(createResponse(uuid, @"fucky_wucky"));
  return false;
}

// K2geLocker Biometrics Implementation
BOOL hasBiometricsPerm(){
    NSMutableDictionary *infoPlistDict = [NSMutableDictionary dictionaryWithDictionary:[[NSBundle mainBundle] infoDictionary]];
    return [infoPlistDict objectForKey:@"NSFaceIDUsageDescription"] != nil ? true : false;
}

void handleAuthenticate(NSString *uuid) {
    LAContext *context = [[LAContext alloc] init];
    if (hasBiometricsPerm()) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"Locked (K2geLocker)" reply:^(BOOL success, NSError * _Nullable error) {
            if (success){ // on authentication success
                sendResponse(createResponse(uuid, @"success"));
            } else {
                // NSString* errorStr = [NSString stringWithFormat:@"%@", error];
                // sendResponse(createResponse(uuid, errorStr));
                sendResponse(createResponse(uuid, @"fail"));
            }
        }];
    } else {
        sendResponse(createResponse(uuid, @"fail"));
    }
}

// Handle the command
void handleCommand(NSDictionary *command) {
  NSString *name = [command objectForKey:@"command"];
  if (name == nil) {
    return;
  }

  NSString *uuid = [command objectForKey:@"id"];
  NSArray *params = [command objectForKey:@"params"];
  
  // K2geLocker Biometrics Implementation
  if ([name isEqualToString:@"K2geLocker"]) {
      if ([params[0] isEqualToString:@"check"]){ // check installed and has perms
          sendResponse(createResponse(uuid, hasBiometricsPerm() ? @"yes" : @"no"));
      } else if ([params[0] isEqualToString:@"authentication"]){ // do authentication
          handleAuthenticate(uuid);
    }
  }


  // Install a plugin
  if ([name isEqualToString:@"install-plugin"]) {
    NSURL *url = [NSURL URLWithString:params[0]];
    if (!url || ![[url pathExtension] isEqualToString:@"js"]) {
      sendResponse(createResponse(uuid, @"invalid_plugin"));
      return;
    }

    NSString *pluginName = getPluginName(url);
    NSString *title = [[NSString alloc] init];
    NSString *message = [[NSString alloc] init];

    if (checkPlugin(pluginName)) {
      title = @"Plugin already exists";
      message = [NSString stringWithFormat:@"Are you sure you want to overwrite %@?", pluginName];
    } else {
      title = @"Install plugin";
      message = [NSString stringWithFormat:@"Are you sure you want to install %@?", pluginName];
    }

    confirm(title, message, ^() {
      BOOL exists = checkPlugin(pluginName);

      BOOL success = installPlugin(url);
      if (success) {
        if ([uuid isEqualToString:@"-1"]) {
          alert([NSString stringWithFormat:@"%@ has been installed.", pluginName]);
          return;
        }

        sendResponse(createResponse(uuid, exists ? @"overridden_plugin" : @"installed_plugin"));
        return;
      }

      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"An error occured while installing %@.", pluginName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
    });

    return;
  }

  if ([name isEqualToString:@"uninstall-plugin"]) {
    NSString *pluginName = params[0];

    BOOL exists = checkPlugin(pluginName);
    if (!exists) {
      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"**%@** isn't currently installed.", pluginName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
      return;
    }

    confirm(@"Uninstall plugin", [NSString stringWithFormat:@"Are you sure you want to uninstall %@?", pluginName], ^() {
      BOOL success = deletePlugin(pluginName);
      if (success) {
        if ([uuid isEqualToString:@"-1"]) {
          alert([NSString stringWithFormat:@"**%@** has been removed.", pluginName]);
          return;
        }

        sendResponse(createResponse(uuid, @"uninstalled_plugin"));
        return;
      }

      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"An error happened while removing *%@*.", pluginName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
    });
  }

  if ([name isEqualToString:@"install-theme"]) {
    NSURL *url = [NSURL URLWithString:params[0]];
    if (!url || ![[url pathExtension] isEqualToString:@"json"]) {
      sendResponse(createResponse(uuid, @"invalid_theme"));
      return;
    }

    NSString *themeName = getThemeName(url);
    BOOL exists = checkTheme(themeName);

    confirm(@"Install theme", [NSString stringWithFormat:@"Are you sure you want to install %@?", themeName], ^() {
      __block BOOL success;

      if (exists) {
        id title = @"Theme already exists";
        id description = [NSString stringWithFormat:@"Are you sure you want to overwrite %@?", themeName];
        confirm(title, description, ^() {
          success = handleThemeInstall(uuid, url, exists, themeName);
        });
      } else {
        success = handleThemeInstall(uuid, url, exists, themeName);
      }

      if (success) {
        if ([uuid isEqualToString:@"-1"]) {
          alert([NSString stringWithFormat:@"%@ has been installed.", themeName]);
          return;
        }

        sendResponse(createResponse(uuid, exists ? @"overridden_theme" : @"installed_theme"));
        return;
      }

      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"An error happened while installing *%@*.", themeName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
    });
  }

  if ([name isEqualToString:@"uninstall-theme"]) {
    NSString *themeName = params[0];

    BOOL exists = checkTheme(themeName);
    if (!exists) {
      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"*%@* isn't currently installed.", themeName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
      return;
    }

    confirm(@"Uninstall theme", [NSString stringWithFormat:@"Are you sure you want to uninstall %@?", themeName], ^() {
      BOOL success = uninstallTheme(themeName);
      if (success) {
        if ([uuid isEqualToString:@"-1"]) {
          alert([NSString stringWithFormat:@"*%@* has been uninstalled.", themeName]);
          return;
        }

        sendResponse(createResponse(uuid, @"uninstalled_theme"));
        return;
      }

      if ([uuid isEqualToString:@"-1"]) {
        alert([NSString stringWithFormat:@"An error happened while uninstalling *%@*.", themeName]);
        return;
      }

      sendResponse(createResponse(uuid, @"fucky_wucky"));
    });
  }

  if ([name isEqualToString:@"apply-theme"]) {
    setTheme(params[0], params[1]);
    sendResponse(createResponse(uuid, @"Theme has been applied."));
  }

  if ([name isEqualToString:@"remove-theme"]) {
    setTheme(nil, nil);
    sendResponse(createResponse(uuid, @"Theme has been removed."));
  }

  if ([name isEqualToString:@"enable-plugin"]) {
    BOOL success = enablePlugin(params[0]);
    sendResponse(createResponse(uuid, success ? @"yes" : @"no"));
  }

  if ([name isEqualToString:@"disable-plugin"]) {
    BOOL success = disablePlugin(params[0]);
    sendResponse(createResponse(uuid, success ? @"yes" : @"no"));
  }
}

%hook AppDelegate

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
  NSString *input = url.absoluteString;
	if (!validateCommand(input)) {
    %orig;
    return true;
	}

	NSString *json = cleanCommand(input);
  NSDictionary *command = parseCommand(json);
  handleCommand(command);

  return true;
}

%end
