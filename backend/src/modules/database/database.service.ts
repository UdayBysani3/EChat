import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import * as dotenv from 'dotenv';

dotenv.config();

@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DatabaseService.name);
  private pool: Pool;

  onModuleInit() {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      this.logger.warn(
        'DATABASE_URL environment variable is missing. Database queries will fail until it is configured.',
      );
      // Create a dummy pool that won't connect, to prevent NestJS startup from crashing
      this.pool = new Pool();
      return;
    }

    try {
      this.pool = new Pool({
        connectionString,
        ssl: connectionString.includes('supabase')
          ? { rejectUnauthorized: false }
          : false,
      });
      this.logger.log('Database pool initialized.');
    } catch (error) {
      this.logger.error('Failed to initialize database pool', error);
    }
  }

  async onModuleDestroy() {
    if (this.pool) {
      await this.pool.end();
      this.logger.log('Database pool closed.');
    }
  }

  // Execute a query
  async query<T extends QueryResultRow = any>(text: string, params?: any[]): Promise<QueryResult<T>> {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'Database connection is not configured. Please set DATABASE_URL environment variable.',
      );
    }
    
    const start = Date.now();
    try {
      const res = await this.pool.query(text, params);
      const duration = Date.now() - start;
      this.logger.debug(`Executed query: ${text} [${duration}ms]`);
      return res;
    } catch (error) {
      this.logger.error(`Error executing query: ${text}`, error);
      throw error;
    }
  }

  // Get a client from pool for transactions
  async getClient(): Promise<PoolClient> {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'Database connection is not configured. Please set DATABASE_URL environment variable.',
      );
    }
    return await this.pool.connect();
  }
}
