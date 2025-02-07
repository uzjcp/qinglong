import { Server, ServerCredentials } from '@grpc/grpc-js';
import { CronService } from '../protos/cron';
import { addCron } from './addCron';
import { delCron } from './delCron';
import { HealthService } from '../protos/health';
import { check } from './health';
import config from '../config';
import Logger from '../loaders/logger';
import { ApiService } from '../protos/api';
import * as Api from './api';

const server = new Server({ 'grpc.enable_http_proxy': 0 });
server.addService(HealthService, { check });
server.addService(CronService, { addCron, delCron });
server.addService(ApiService, Api);
server.bindAsync(
  `0.0.0.0:${config.cronPort}`,
  ServerCredentials.createInsecure(),
  (err, port) => {
    if (err) {
      throw err;
    }
    Logger.debug(`✌️ 定时服务启动成功！`);
    console.debug(`✌️ 定时服务启动成功！`);
    process.send?.('ready');
  },
);
