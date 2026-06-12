import { Controller, Get, UseGuards, Req } from '@nestjs/common';
import { AppService } from './app.service';
import { AuthGuard } from './common/guards/auth.guard';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Get('health')
  getHealth() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
    };
  }

  @Get('auth/test')
  @UseGuards(AuthGuard)
  testAuth(@Req() req: any) {
    return {
      message: 'Authentication successful!',
      user: req.user,
    };
  }
}
