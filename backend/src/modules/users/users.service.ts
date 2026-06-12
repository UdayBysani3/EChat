import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class UsersService {
  constructor(private readonly databaseService: DatabaseService) {}

  async getProfile(userId: string) {
    const result = await this.databaseService.query(
      'SELECT id, email, username, profile_image, bio, status, created_at FROM public.users WHERE id = $1',
      [userId],
    );
    if (result.rows.length === 0) {
      throw new NotFoundException('User profile not found');
    }
    return result.rows[0];
  }

  async updateProfile(
    userId: string,
    data: { username?: string; bio?: string; profile_image?: string; status?: string },
  ) {
    const updates: string[] = [];
    const values: any[] = [userId];
    let index = 2;

    if (data.username !== undefined) {
      // Validate username regex (alphanumeric + underscores/dots, 3-20 chars)
      if (data.username && !/^[a-zA-Z0-9_.]{3,20}$/.test(data.username)) {
        throw new BadRequestException(
          'Username must be between 3 and 20 characters and contain only alphanumeric characters, underscores, or dots.',
        );
      }
      updates.push(`username = $${index++}`);
      values.push(data.username);
    }
    if (data.bio !== undefined) {
      updates.push(`bio = $${index++}`);
      values.push(data.bio);
    }
    if (data.profile_image !== undefined) {
      updates.push(`profile_image = $${index++}`);
      values.push(data.profile_image);
    }
    if (data.status !== undefined) {
      if (data.status && !['online', 'offline', 'away'].includes(data.status)) {
        throw new BadRequestException('Invalid status value');
      }
      updates.push(`status = $${index++}`);
      values.push(data.status);
    }

    if (updates.length === 0) {
      return this.getProfile(userId);
    }

    const queryText = `
      UPDATE public.users
      SET ${updates.join(', ')}
      WHERE id = $1
      RETURNING id, email, username, profile_image, bio, status, created_at
    `;

    try {
      const result = await this.databaseService.query(queryText, values);
      if (result.rows.length === 0) {
        throw new NotFoundException('User profile not found');
      }
      return result.rows[0];
    } catch (error) {
      if (error.code === '23505') {
        throw new BadRequestException('Username is already taken');
      }
      throw error;
    }
  }

  async searchUserByEmail(email: string) {
    const result = await this.databaseService.query(
      'SELECT id, email, username, profile_image, bio, status FROM public.users WHERE email = $1',
      [email.trim().toLowerCase()],
    );
    if (result.rows.length === 0) {
      throw new NotFoundException('No user found with the specified email');
    }
    return result.rows[0];
  }
}
