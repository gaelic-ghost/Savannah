#!/usr/bin/env node
import { createSavannahClient } from "./savannah-client.mjs";

const info = await createSavannahClient().getInfo();
console.log(JSON.stringify({
  ok: true,
  extensions: info.extensions,
  message: "Safari extension state is unproven until the Savannah app exposes SpiderWeb and SafariTourGuide status."
}, null, 2));

