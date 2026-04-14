import loki from 'k6/x/loki';
import { sleep } from 'k6';

export const options = {
  vus: 2,
  duration: "4s",
  thresholds: {
    http_req_failed: ['rate==0'],
  }
}

const loki_url = "http://fake@loki:3100"
const conf = loki.Config(loki_url);
const client = loki.Client(conf);

export default function () {
  const streams = 2;
  const minSize = 64;
  const maxSize = 256;
  const res = client.pushParameterized(streams, minSize, maxSize);
  sleep(1);
};
