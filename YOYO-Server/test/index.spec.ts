// test/index.spec.ts
import { env, createExecutionContext, waitOnExecutionContext, SELF } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import worker from '../src/index';
import { generateShareCode } from '../src/shareCode';

// For now, you'll need to do something like this to get a correctly-typed
// `Request` to pass to `worker.fetch()`.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;


describe('Worker', () => {
	it('responds with YOYO API (unit style)', async () => {
		const request = new IncomingRequest('http://example.com');
		// Create an empty context to pass to `worker.fetch()`.
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		// Wait for all `Promise`s passed to `ctx.waitUntil()` to settle before running test assertions
		await waitOnExecutionContext(ctx);
		expect(await response.text()).toMatchInlineSnapshot(`"YOYO API"`);
	});

	it('responds with YOYO API (integration style)', async () => {
		const response = await SELF.fetch('https://example.com');
		expect(await response.text()).toMatchInlineSnapshot(`"YOYO API"`);
	});
});

describe('generateShareCode', () => {
	it('generates 6 digits on first attempt', () => {
		const code = generateShareCode(0);
		expect(code).toMatch(/^\d{6}$/);
	});

	it('adds prefixed letters on conflicts (excluding O/I)', () => {
		const letter = '[A-HJ-NP-Z]';
		expect(generateShareCode(1)).toMatch(new RegExp(`^${letter}\\d{5}$`));
		expect(generateShareCode(2)).toMatch(new RegExp(`^${letter}{2}\\d{4}$`));
		expect(generateShareCode(6)).toMatch(new RegExp(`^${letter}{6}$`));

		const samples = [generateShareCode(1), generateShareCode(2), generateShareCode(6)].join('');
		expect(samples).not.toContain('O');
		expect(samples).not.toContain('I');
	});
});
