#!/usr/bin/env node
import { createSavannahClient } from "./savannah-client.mjs";

const client = createSavannahClient();
console.log(JSON.stringify(await client.getInfo(), null, 2));

