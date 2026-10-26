import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./e2e',workers:1,timeout:90000,use:{headless:true},reporter:'list'});
