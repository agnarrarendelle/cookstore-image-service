import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

/**
 *
 * Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
 * @param {Object} event - API Gateway Lambda Proxy Input Format
 *
 * Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
 * @returns {Object} object - API Gateway Lambda Proxy Output Format
 *
 */

interface GetSignedUrlBody {
  imageKey: string;
}

export const lambdaHandler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  const s3Client = new S3Client({ region: process.env.AWS_REGION });

  if (!event.pathParameters) {
    const body: GetSignedUrlBody = JSON.parse(event.body!);
    const command = new PutObjectCommand({
      Bucket: process.env.UploadBucket,
      Key: body.imageKey,
      ContentType: "image/png",
    });
    const url = await getSignedUrl(s3Client, command, { expiresIn: 600 });
    try {
      return {
        statusCode: 200,
        body: JSON.stringify({
          url: url,
        }),
      };
    } catch (err) {
      console.log(err);
      return {
        statusCode: 500,
        body: JSON.stringify({
          message: "some error happened",
        }),
      };
    }
  } else {
    console.log(event.pathParameters)
    const id = event.pathParameters.id;
    const command = new GetObjectCommand({
      Bucket: process.env.UploadBucket,
      Key: id,
    });
    console.log("here 1")
    const url = await getSignedUrl(s3Client, command, {
      expiresIn: 24 * 60 * 60,
    });
    console.log("here 2")

    try {
      return {
        statusCode: 200,
        body: JSON.stringify({
          url: url,
        }),
      };
    } catch (err) {
      console.log(err);
      return {
        statusCode: 500,
        body: JSON.stringify({
          message: "some error happened",
        }),
      };
    }
  }
};
