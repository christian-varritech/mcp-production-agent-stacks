#!/usr/bin/env node

/**
 * MCP Production Agent Server - Starter Implementation
 * 
 * This is a minimal MCP server demonstrating intelligent task routing
 * and caching for cost optimization.
 * 
 * Install: npm install @modelcontextprotocol/sdk
 * Run: node mcp-server.js
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

// Simple in-memory cache with TTL
class Cache {
  constructor(defaultTTL = 300000) { // 5 minutes default
    this.store = new Map();
    this.defaultTTL = defaultTTL;
  }

  get(key) {
    const item = this.store.get(key);
    if (!item) return null;
    
    if (Date.now() > item.expiry) {
      this.store.delete(key);
      return null;
    }
    
    return item.data;
  }

  set(key, data, ttl = this.defaultTTL) {
    this.store.set(key, {
      data,
      expiry: Date.now() + ttl
    });
  }
}

const cache = new Cache();

// Model routing configuration
const ROUTING_CONFIG = {
  simple: {
    patterns: ['classify', 'sentiment', 'extract', 'summarize'],
    model: 'local-llama-3.1-8b',
    costPer1k: 0.02
  },
  complex: {
    patterns: ['code', 'reason', 'analyze', 'debug'],
    model: 'claude-sonnet-4',
    costPer1k: 0.15
  },
  creative: {
    patterns: ['write', 'create', 'design', 'brainstorm'],
    model: 'gpt-5-turbo',
    costPer1k: 0.50
  }
};

function routeTask(task) {
  const lowerTask = task.toLowerCase();
  
  for (const [tier, config] of Object.entries(ROUTING_CONFIG)) {
    if (config.patterns.some(p => lowerTask.includes(p))) {
      return { tier, ...config };
    }
  }
  
  // Default to complex for unknown tasks
  return { tier: 'complex', ...ROUTING_CONFIG.complex };
}

const server = new Server(
  {
    name: 'mcp-production-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'route_task',
        description: 'Route a task to the optimal model based on complexity',
        inputSchema: {
          type: 'object',
          properties: {
            task: {
              type: 'string',
              description: 'The task to route'
            }
          },
          required: ['task']
        }
      },
      {
        name: 'cached_query',
        description: 'Execute a query with automatic caching',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'The query to execute'
            },
            ttl: {
              type: 'number',
              description: 'Cache TTL in milliseconds (default: 300000)'
            }
          },
          required: ['query']
        }
      },
      {
        name: 'estimate_cost',
        description: 'Estimate the cost of running a task',
        inputSchema: {
          type: 'object',
          properties: {
            task: {
              type: 'string',
              description: 'The task to estimate'
            },
            tokens: {
              type: 'number',
              description: 'Estimated token count'
            }
          },
          required: ['task', 'tokens']
        }
      }
    ]
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case 'route_task': {
      const routing = routeTask(args.task);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              recommended_model: routing.model,
              tier: routing.tier,
              cost_per_1k_tokens: routing.costPer1k,
              reason: `Task matched ${routing.tier} complexity patterns`
            }, null, 2)
          }
        ]
      };
    }

    case 'cached_query': {
      const cacheKey = `query:${args.query}`;
      const cached = cache.get(cacheKey);
      
      if (cached) {
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                source: 'cache',
                data: cached,
                cached_at: 'previous request'
              }, null, 2)
            }
          ]
        };
      }
      
      // Simulate API call (replace with actual implementation)
      const result = {
        data: `Result for: ${args.query}`,
        timestamp: new Date().toISOString()
      };
      
      cache.set(cacheKey, result, args.ttl);
      
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              source: 'api',
              data: result,
              cached: true
            }, null, 2)
          }
        ]
      };
    }

    case 'estimate_cost': {
      const routing = routeTask(args.task);
      const cost = (args.tokens / 1000) * routing.costPer1k;
      
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              model: routing.model,
              tier: routing.tier,
              tokens: args.tokens,
              estimated_cost_usd: cost.toFixed(4),
              optimization_tip: cost > 1.0 
                ? 'Consider caching or self-hosting for this workload'
                : 'Cost-efficient for API usage'
            }, null, 2)
          }
        ]
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('MCP Production Server running on stdio');
}

main().catch((error) => {
  console.error('Server error:', error);
  process.exit(1);
});
