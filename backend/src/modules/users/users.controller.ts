import {
  Controller,
  Get,
  Patch,
  Body,
  Query,
  UseGuards,
  Req,
  BadRequestException,
} from '@nestjs/common';
import { UsersService } from './users.service';
import { AuthGuard } from '../../common/guards/auth.guard';

@Controller('users')
@UseGuards(AuthGuard)
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  async getMe(@Req() req: any) {
    const userId = req.user.id;
    return await this.usersService.getProfile(userId);
  }

  @Patch('profile')
  async updateProfile(
    @Req() req: any,
    @Body()
    body: {
      username?: string;
      bio?: string;
      profile_image?: string;
      status?: string;
    },
  ) {
    const userId = req.user.id;
    return await this.usersService.updateProfile(userId, body);
  }

  @Get('search')
  async searchUser(@Query('email') email: string) {
    if (!email) {
      throw new BadRequestException('Email query parameter is required');
    }
    return await this.usersService.searchUserByEmail(email);
  }
}
